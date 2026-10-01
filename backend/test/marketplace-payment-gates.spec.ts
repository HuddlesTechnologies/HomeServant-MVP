import { PrismaClient, UserRole } from '@prisma/client';
import { MarketplaceOrdersService } from '../src/marketplace-orders/marketplace-orders.service';
import { makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

/// A marketplace item only counts as paid once Paystack has confirmed the
/// charge (PAID_HELD): a pending or failed checkout can't be shipped, and
/// the vendor sees which it is.
describeDb('marketplace items before payment clears (real Postgres)', () => {
  let prisma: PrismaClient;
  let orders: MarketplaceOrdersService;
  let shipments: number;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    shipments = 0;
  });

  async function orderItem(paymentStatus: 'INITIATED' | 'FAILED' | 'PAID_HELD') {
    const vendorUser = await makeUser(prisma, UserRole.VENDOR);
    const buyer = await makeUser(prisma, UserRole.TENANT);
    const vendor = await prisma.vendorProfile.create({
      data: { userId: vendorUser.id, businessName: 'Test Shop', category: 'FURNITURE', state: 'Lagos' },
    });
    const product = await prisma.product.create({
      data: { vendorId: vendor.id, name: 'Chair', description: 'A chair', price: 10_000, stock: 5, category: 'FURNITURE', fulfillmentOptions: ['DELIVERY'] },
    });
    const order = await prisma.marketplaceOrder.create({
      data: {
        buyerId: buyer.id,
        paymentMethod: 'CARD',
        customerName: 'Buyer',
        customerPhone: '08000000000',
        customerAddress: '1 Test Street, Lagos',
        items: { create: [{ productId: product.id, vendorId: vendor.id, productName: 'Chair', unitPrice: 10_000, quantity: 1, fulfillment: 'DELIVERY' }] },
      },
      include: { items: true },
    });
    const item = order.items[0];
    await prisma.payment.create({
      data: {
        purpose: 'MARKETPLACE_ORDER_ITEM',
        orderItemId: item.id,
        payerId: buyer.id,
        recipientUserId: vendorUser.id,
        amount: 10_000_00,
        platformFeeAmount: 500_00,
        paystackReference: `mkt-${item.id}`,
        status: paymentStatus,
      },
    });
    const vendors = { requireOwn: async () => vendor };
    const delivery = {
      createShipment: async () => {
        shipments++;
        return { shipmentId: 'SHP_1', trackingNumber: 'TRK_1' };
      },
    };
    orders = new MarketplaceOrdersService(prisma as never, vendors as never, { create: async () => undefined } as never, {} as never, delivery as never);
    return { vendorUser, item };
  }

  it.each(['INITIATED', 'FAILED'] as const)('a %s payment: the item cannot be shipped', async (status) => {
    const { vendorUser, item } = await orderItem(status);
    await expect(orders.shipItem(vendorUser.id, item.id, {} as never)).rejects.toThrow("hasn't paid");
    expect(shipments).toBe(0);
  });

  it("the vendor's order list carries each item's payment status", async () => {
    const { vendorUser } = await orderItem('INITIATED');
    const [row] = await orders.findForVendor(vendorUser.id);
    expect(row.payment?.status).toBe('INITIATED');
  });

  it('a paid (held) item can be shipped', async () => {
    const { vendorUser, item } = await orderItem('PAID_HELD');
    await orders.shipItem(vendorUser.id, item.id, {} as never);
    expect(shipments).toBe(1);
  });
});
