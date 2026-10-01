import { PrismaClient, UserRole } from '@prisma/client';
import { MarketplaceOrdersService } from '../src/marketplace-orders/marketplace-orders.service';
import { PaymentsService } from '../src/payments/payments.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { fakeMail, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

/// A stand-in for Paystack's charge and refund endpoints.
function fakePaystack() {
  return {
    initialized: [] as { amount: number; reference: string }[],
    charges: new Map<string, string>(), // reference -> Paystack charge status
    refunds: [] as { reference: string; amount?: number }[],
    failInitialize: false,
    refundNext: null as null | 'acceptedThenTimeout',
    async initializeTransaction(_email: string, amount: number, reference: string) {
      if (this.failInitialize) throw new Error('Paystack is unavailable');
      this.initialized.push({ amount, reference });
      this.charges.set(reference, 'abandoned');
      return { reference, authorizationUrl: `https://checkout.paystack.test/${reference}` };
    },
    async verifyCharge(reference: string) {
      return this.charges.get(reference) ?? 'not_found';
    },
    async refundedSoFar(reference: string) {
      return this.refunds.filter((r: { reference: string }) => r.reference === reference).reduce((sum: number, r: { amount?: number }) => sum + (r.amount ?? 999_999_999), 0);
    },
    async refundTransaction(reference: string, amount?: number) {
      this.refunds.push({ reference, amount });
      if (this.refundNext === 'acceptedThenTimeout') {
        this.refundNext = null;
        throw new Error('Request timed out'); // Paystack DID refund it
      }
    },
  };
}

describeDb('marketplace orders paid in one checkout (real Postgres)', () => {
  let prisma: PrismaClient;
  let paystack: ReturnType<typeof fakePaystack>;
  let payments: PaymentsService;
  let orders: MarketplaceOrdersService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    paystack = fakePaystack();
    const notifier = { create: async () => undefined };
    const mail = fakeMail();
    const settings = new PlatformSettingsService(prisma as never, notifier as never, mail as never);
    const chat = { postBookingSystemMessage: async () => undefined };
    payments = new PaymentsService(prisma as never, paystack as never, notifier as never, mail as never, chat as never, settings);
  });

  /// Two vendors, one product each, and a buyer ready to check out.
  async function shop() {
    const buyer = await makeUser(prisma, UserRole.TENANT, { phoneNumber: '08000000000', houseAddress: '1 Test Street, Lagos' } as never);
    const products: Awaited<ReturnType<PrismaClient['product']['create']>>[] = [];
    const vendors: Awaited<ReturnType<PrismaClient['vendorProfile']['create']>>[] = [];
    for (const [name, price] of [
      ['Chair', 10_000],
      ['Lamp', 4_000],
    ] as const) {
      const user = await makeUser(prisma, UserRole.VENDOR);
      const vendor = await prisma.vendorProfile.create({ data: { userId: user.id, businessName: `${name} Shop`, category: 'FURNITURE', state: 'Lagos' } });
      vendors.push(vendor);
      products.push(
        await prisma.product.create({
          data: { vendorId: vendor.id, name, description: `A ${name}`, price, stock: 5, category: 'FURNITURE', fulfillmentOptions: ['DELIVERY'] },
        }),
      );
    }
    const vendorsService = { requireOwn: async (userId: string) => vendors.find((v) => v.userId === userId)! };
    orders = new MarketplaceOrdersService(prisma as never, vendorsService as never, { create: async () => undefined } as never, payments, {} as never);
    return { buyer, products, vendors };
  }

  async function placeOrder() {
    const { buyer, products, vendors } = await shop();
    const order = await orders.create(buyer.id, {
      paymentMethod: 'CARD',
      items: [
        { productId: products[0].id, quantity: 2, fulfillment: 'DELIVERY' },
        { productId: products[1].id, quantity: 1, fulfillment: 'DELIVERY' },
      ],
    } as never);
    return { buyer, products, vendors, order, reference: order.checkout.reference };
  }

  const stock = async (id: string) => (await prisma.product.findUniqueOrThrow({ where: { id } })).stock;
  const itemPayments = (reference: string) => prisma.payment.findMany({ where: { chargeReference: reference }, orderBy: { amount: 'desc' } });

  it('a two-vendor cart is one charge for the total, and counts as paid only once Paystack confirms it', async () => {
    const { order, reference } = await placeOrder();
    expect(paystack.initialized).toEqual([{ amount: (2 * 10_000 + 4_000) * 100, reference }]);
    expect(order.checkout.authorizationUrl).toContain(reference);
    expect((await itemPayments(reference)).map((p) => p.status)).toEqual(['INITIATED', 'INITIATED']);

    await payments.handleChargeSuccess(reference);
    const paid = await itemPayments(reference);
    expect(paid.map((p) => [p.amount, p.status])).toEqual([
      [20_000_00, 'PAID_HELD'],
      [4_000_00, 'PAID_HELD'],
    ]);
    // A repeated webhook changes nothing.
    await payments.handleChargeSuccess(reference);
    expect((await itemPayments(reference)).map((p) => p.status)).toEqual(['PAID_HELD', 'PAID_HELD']);
  });

  it('the buyer coming back from Paystack confirms the order only if Paystack says it was paid', async () => {
    const { buyer, reference } = await placeOrder();
    await expect(orders.confirmPayment(buyer.id, reference)).resolves.toEqual({ paid: false });
    expect((await itemPayments(reference)).map((p) => p.status)).toEqual(['INITIATED', 'INITIATED']);
    paystack.charges.set(reference, 'success');
    await expect(orders.confirmPayment(buyer.id, reference)).resolves.toEqual({ paid: true });
    expect((await itemPayments(reference)).map((p) => p.status)).toEqual(['PAID_HELD', 'PAID_HELD']);
  });

  it('each item is refunded on its own from the shared charge, never twice', async () => {
    const { vendors, order, reference } = await placeOrder();
    await payments.handleChargeSuccess(reference);
    const [chairItem, lampItem] = [...order.items].sort((a, b) => b.unitPrice - a.unitPrice);

    // The chair's refund reaches Paystack but we see a timeout.
    paystack.refundNext = 'acceptedThenTimeout';
    await expect(orders.respondToItem(vendors[0].userId, chairItem.id, { status: 'CANCELLED' } as never)).rejects.toThrow('timed out');
    // The lamp is still refunded, for its own amount.
    await orders.respondToItem(vendors[1].userId, lampItem.id, { status: 'CANCELLED' } as never);
    // Retrying the chair records it without refunding it again.
    await orders.respondToItem(vendors[0].userId, chairItem.id, { status: 'CANCELLED' } as never);

    expect(paystack.refunds).toEqual([
      { reference, amount: 20_000_00 },
      { reference, amount: 4_000_00 },
    ]);
    expect((await itemPayments(reference)).map((p) => p.status)).toEqual(['REFUNDED', 'REFUNDED']);
  });

  it('an order not paid in time is cancelled and its stock put back; one still clearing is left alone', async () => {
    const { products, reference } = await placeOrder();
    expect([await stock(products[0].id), await stock(products[1].id)]).toEqual([3, 4]);
    const later = new Date(Date.now() + 2 * 60 * 60 * 1000);

    paystack.charges.set(reference, 'ongoing');
    expect(await payments['checkout'].expireUnpaid((ref) => payments.handleChargeSuccess(ref), later)).toBe(0);

    paystack.charges.set(reference, 'abandoned');
    expect(await payments['checkout'].expireUnpaid((ref) => payments.handleChargeSuccess(ref), later)).toBe(1);
    expect((await itemPayments(reference)).map((p) => p.status)).toEqual(['FAILED', 'FAILED']);
    expect([await stock(products[0].id), await stock(products[1].id)]).toEqual([5, 5]);
    const items = await prisma.marketplaceOrderItem.findMany();
    expect(items.map((i) => i.status)).toEqual(['CANCELLED', 'CANCELLED']);
  });

  it('a charge that did succeed is processed at expiry instead of cancelled', async () => {
    const { products, reference } = await placeOrder();
    paystack.charges.set(reference, 'success');
    await payments['checkout'].expireUnpaid((ref) => payments.handleChargeSuccess(ref), new Date(Date.now() + 2 * 60 * 60 * 1000));
    expect((await itemPayments(reference)).map((p) => p.status)).toEqual(['PAID_HELD', 'PAID_HELD']);
    expect(await stock(products[0].id)).toBe(3);
  });

  it('a payment arriving after the order was cancelled is refunded in full, once', async () => {
    const { reference } = await placeOrder();
    await payments['checkout'].expireUnpaid((ref) => payments.handleChargeSuccess(ref), new Date(Date.now() + 2 * 60 * 60 * 1000));
    await payments.handleChargeSuccess(reference);
    await payments.handleChargeSuccess(reference);
    expect(paystack.refunds).toEqual([{ reference, amount: undefined }]);
    expect((await itemPayments(reference)).map((p) => p.status)).toEqual(['REFUNDED', 'REFUNDED']);
  });

  it("if the checkout can't be started, the order is cancelled and its stock put back", async () => {
    const { buyer, products } = await shop();
    paystack.failInitialize = true;
    await expect(
      orders.create(buyer.id, { paymentMethod: 'CARD', items: [{ productId: products[0].id, quantity: 2, fulfillment: 'DELIVERY' }] } as never),
    ).rejects.toThrow("Couldn't start the payment");
    expect(await stock(products[0].id)).toBe(5);
    expect((await prisma.marketplaceOrderItem.findFirstOrThrow()).status).toBe('CANCELLED');
  });
});
