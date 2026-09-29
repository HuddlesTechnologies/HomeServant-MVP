import { PrismaClient, UserRole } from '@prisma/client';
import { isLowBalanceError, PaymentsService } from '../src/payments/payments.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { changesAdminQueues } from '../src/prisma/prisma.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describe('admin badges refresh when their records change', () => {
  it('evictions, payments and ID checks — writes only', () => {
    expect(changesAdminQueues('EvictionRequest', 'create')).toBe(true);
    expect(changesAdminQueues('EvictionRequest', 'updateMany')).toBe(true);
    expect(changesAdminQueues('Payment', 'update')).toBe(true);
    expect(changesAdminQueues('IdentityVerification', 'upsert')).toBe(true);
    expect(changesAdminQueues('Payment', 'findMany')).toBe(false);
    expect(changesAdminQueues('Message', 'create')).toBe(false);
  });

  it("recognises Paystack's low-balance errors", () => {
    expect(isLowBalanceError('Your balance is not enough to fulfil this request')).toBe(true);
    expect(isLowBalanceError('Insufficient balance')).toBe(true);
    expect(isLowBalanceError('Request timed out')).toBe(false);
    expect(isLowBalanceError(null)).toBe(false);
  });
});

describeDb('payouts and a low Paystack balance (real Postgres)', () => {
  let prisma: PrismaClient;
  let payments: PaymentsService;
  let paystack: {
    balance: number;
    sent: string[];
    balanceKobo(): Promise<number>;
    createTransferRecipient(): Promise<string>;
    verifyTransfer(reference: string): Promise<string>;
    initiateTransfer(amount: number, code: string, reason: string, reference: string): Promise<void>;
  };

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    paystack = {
      balance: 0,
      sent: [],
      async balanceKobo() {
        return this.balance;
      },
      async createTransferRecipient() {
        return 'RCP_1';
      },
      async verifyTransfer(reference: string) {
        return this.sent.includes(reference) ? 'success' : 'not_found';
      },
      async initiateTransfer(amount: number, _code: string, _reason: string, reference: string) {
        if (amount > this.balance) throw new Error('Your balance is not enough to fulfil this request');
        this.balance -= amount;
        this.sent.push(reference);
      },
    };
    const notifier = { create: async () => undefined };
    const mail = fakeMail();
    const settings = new PlatformSettingsService(prisma as never, notifier as never, mail as never);
    const chat = { postBookingSystemMessage: async () => undefined };
    payments = new PaymentsService(prisma as never, paystack as never, notifier as never, mail as never, chat as never, settings);
  });

  /// A tenant ready to move in, rent (₦1,000,000, landlord's share ₦950,000) held.
  async function awaitingMoveIn() {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    await prisma.user.update({ where: { id: landlord.id }, data: { bankCode: '058', accountNumber: '0123456789', accountName: 'Test Landlord' } });
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const property = await makeProperty(prisma, landlord.id);
    await prisma.property.update({ where: { id: property.id }, data: { rentDurationMonths: 12 } });
    const booking = await prisma.booking.create({ data: { propertyId: property.id, tenantId: tenant.id, status: 'INSPECTION_CONFIRMED' } });
    const payment = await prisma.payment.create({
      data: {
        purpose: 'RENTAL_BOOKING',
        bookingId: booking.id,
        payerId: tenant.id,
        recipientUserId: landlord.id,
        amount: 1_000_000_00,
        platformFeeAmount: 50_000_00,
        paystackReference: `ref-${booking.id}`,
        status: 'PAID_HELD',
        paidAt: new Date(),
      },
    });
    return { tenant, booking, payment };
  }

  it("doesn't send a payout the balance can't cover, says why, and doesn't count it as an attempt", async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.balance = 100_000_00;
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);

    const row = await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
    expect(row.status).toBe('PAID_HELD');
    expect(row.payoutAttempts).toBe(0);
    expect(row.payoutLastError).toMatch(/Paystack balance is too low.*NGN 100,000 available.*NGN 950,000 needed/);
    await expect(payments.retryPayout(payment.id)).rejects.toThrow(/Paystack balance is too low/);
    expect(paystack.sent).toEqual([]);
  });

  it('retries automatically once the balance is funded, oldest first, and stops when it runs out', async () => {
    const first = await awaitingMoveIn();
    const second = await awaitingMoveIn();
    await payments.releaseBookingOnMovedIn(first.booking.id, first.tenant.id);
    await payments.releaseBookingOnMovedIn(second.booking.id, second.tenant.id);
    expect(await payments.retryLowBalancePayouts()).toBe(0);

    paystack.balance = 1_000_000_00; // enough for one ₦950,000 payout
    expect(await payments.retryLowBalancePayouts()).toBe(1);
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: first.payment.id } })).status).toBe('RELEASED');
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: second.payment.id } })).status).toBe('PAID_HELD');

    paystack.balance += 950_000_00;
    expect(await payments.retryLowBalancePayouts()).toBe(1);
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: second.payment.id } })).status).toBe('RELEASED');
    expect(paystack.sent).toHaveLength(2);
    expect(await payments.retryLowBalancePayouts()).toBe(0);
  });

  it("when Paystack itself refuses for balance, the error is explained the same way", async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.balanceKobo = async () => {
      throw new Error('unreachable');
    };
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    const row = await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
    expect(row.payoutLastError).toMatch(/Paystack balance is too low.*balance unknown/);
  });
});
