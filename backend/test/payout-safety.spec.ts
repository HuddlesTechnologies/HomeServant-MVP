import { BadRequestException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { PaymentsService } from '../src/payments/payments.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

/// A stand-in for Paystack that remembers every transfer by reference —
/// exactly what the real verify endpoint lets the service ask.
function fakePaystack() {
  return {
    transfers: new Map<string, string>(), // reference -> Paystack status
    sent: [] as string[],
    next: null as null | 'rejected' | 'acceptedThenTimeout',
    delayMs: 0,
    refunds: new Map<string, number[]>(), // charge reference -> refunded amounts
    refundCalls: 0,
    refundNext: null as null | 'rejected' | 'acceptedThenTimeout',
    async refundedSoFar(reference: string) {
      return (this.refunds.get(reference) ?? []).reduce((a: number, b: number) => a + b, 0);
    },
    async refundTransaction(reference: string, amount?: number) {
      if (this.delayMs) await new Promise((r) => setTimeout(r, this.delayMs));
      this.refundCalls++;
      if (this.refundNext === 'rejected') {
        this.refundNext = null;
        throw new Error('Paystack is unavailable');
      }
      this.refunds.set(reference, [...(this.refunds.get(reference) ?? []), amount ?? 1_000_000_00]);
      if (this.refundNext === 'acceptedThenTimeout') {
        this.refundNext = null;
        throw new Error('Request timed out');
      }
    },
    async createTransferRecipient() {
      return 'RCP_1';
    },
    async verifyTransfer(reference: string) {
      return this.transfers.get(reference) ?? 'not_found';
    },
    async initiateTransfer(_amount: number, _code: string, _reason: string, reference: string) {
      if (this.delayMs) await new Promise((r) => setTimeout(r, this.delayMs));
      if (this.next === 'rejected') {
        this.next = null;
        throw new Error('Insufficient balance'); // nothing created at Paystack
      }
      this.transfers.set(reference, 'success');
      this.sent.push(reference);
      if (this.next === 'acceptedThenTimeout') {
        this.next = null;
        throw new Error('Request timed out'); // Paystack DID send it
      }
    },
  };
}

describeDb('payouts can never be sent twice (real Postgres)', () => {
  let prisma: PrismaClient;
  let paystack: ReturnType<typeof fakePaystack>;
  let payments: PaymentsService;
  let settings: PlatformSettingsService;

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
    void notifier;
    const mail = fakeMail();
    settings = new PlatformSettingsService(prisma as never, notifier as never, mail as never);
    const chat = { postBookingSystemMessage: async () => undefined };
    payments = new PaymentsService(prisma as never, paystack as never, notifier as never, mail as never, chat as never, settings);
  });

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
    return { landlord, tenant, booking, payment };
  }

  const status = (id: string) => prisma.payment.findUniqueOrThrow({ where: { id } });

  it('Paystack sent it but we saw an error: the tenant still moves in, and Retry records it as paid without sending again', async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.next = 'acceptedThenTimeout';
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);

    expect((await prisma.booking.findUniqueOrThrow({ where: { id: booking.id } })).status).toBe('MOVED_IN');
    expect((await status(payment.id)).status).toBe('PAID_HELD');
    const [stuck] = await payments.stuckPayouts();
    expect(stuck.paymentId).toBe(payment.id);
    expect(stuck.reason).toBe('FAILED');
    expect(stuck.lastError).toMatch(/timed out/);

    await expect(payments.retryPayout(payment.id)).resolves.toEqual({ status: 'PAID' });
    expect(paystack.sent).toEqual([payment.id]); // exactly one transfer ever
    expect((await status(payment.id)).status).toBe('RELEASED');
    expect(await payments.stuckPayouts()).toHaveLength(0);
    await expect(payments.retryPayout(payment.id)).resolves.toEqual({ status: 'ALREADY_PAID' });
    expect(paystack.sent).toHaveLength(1);
  });

  it('Paystack refused it: Retry sends it once, with the same reference', async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.next = 'rejected';
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect(paystack.sent).toEqual([]);
    await payments.retryPayout(payment.id);
    expect(paystack.sent).toEqual([payment.id]);
  });

  it('two retries at the same moment send only one transfer', async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.next = 'rejected';
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    paystack.delayMs = 150;
    const results = await Promise.allSettled([payments.retryPayout(payment.id), payments.retryPayout(payment.id)]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    expect(paystack.sent).toEqual([payment.id]);
    expect((await status(payment.id)).status).toBe('RELEASED');
  });

  it('failed at the bank after release: back to owed, and Retry uses a fresh reference (once)', async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect((await status(payment.id)).status).toBe('RELEASED');

    paystack.transfers.set(payment.id, 'reversed');
    await payments.handleTransferFailed(payment.id, 'reversed', 'Account closed');
    const owed = await status(payment.id);
    expect(owed.status).toBe('PAID_HELD');
    expect(owed.payoutLastError).toMatch(/reversed.*Account closed/);
    expect((await payments.stuckPayouts())[0].reason).toBe('FAILED');

    await payments.retryPayout(payment.id);
    expect(paystack.sent).toEqual([payment.id, `${payment.id}-r2`]);
    expect((await status(payment.id)).payoutReference).toBe(`${payment.id}-r2`);
  });

  it('Retry is refused while a payout is waiting for verification, and for escrow before move-in', async () => {
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    const { tenant, booking, payment } = await awaitingMoveIn();
    await expect(payments.retryPayout(payment.id)).rejects.toBeInstanceOf(BadRequestException); // not moved in yet
    expect(await payments.stuckPayouts()).toHaveLength(0);

    await settings.update(admin.id, { payUnverifiedLandlords: false });
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    const [held] = await payments.stuckPayouts();
    expect(held.reason).toBe('AWAITING_VERIFICATION');
    expect(held.canRetry).toBe(false);
    await expect(payments.retryPayout(payment.id)).rejects.toBeInstanceOf(BadRequestException);
    expect(paystack.sent).toEqual([]);
  });

  // --- Refunds -----------------------------------------------------------

  const refundsOf = (p: { paystackReference: string }) => paystack.refunds.get(p.paystackReference) ?? [];

  it('a tenant refund that timed out after Paystack took it is never sent again', async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.refundNext = 'acceptedThenTimeout';
    await expect(payments.refundBookingBeforeMoveIn(booking.id, tenant.id)).rejects.toThrow(/timed out/);
    expect((await status(payment.id)).status).toBe('PAID_HELD');
    const [row] = await payments.stuckPayouts();
    expect(row.kind).toBe('REFUND');
    expect(row.canRetryRefund).toBe(true);

    // The tenant tries again: Paystack already has it, so it's recorded, not re-sent.
    await payments.refundBookingBeforeMoveIn(booking.id, tenant.id);
    expect(refundsOf(payment)).toHaveLength(1);
    expect((await status(payment.id)).status).toBe('REFUNDED');
    await expect(payments.refundBookingBeforeMoveIn(booking.id, tenant.id)).rejects.toThrow(/already been refunded/);
    expect(paystack.refundCalls).toBe(1);
  });

  it('after an admin refund the tenant cannot refund again, and it cannot be refunded twice', async () => {
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    const { tenant, booking, payment } = await awaitingMoveIn();
    await expect(payments.adminRefundBooking(payment.id, admin.id, 'short')).rejects.toBeInstanceOf(BadRequestException);
    await payments.adminRefundBooking(payment.id, admin.id, 'Landlord could not hand over the keys');

    const refunded = await status(payment.id);
    expect(refunded.status).toBe('REFUNDED');
    expect(refunded.refundedById).toBe(admin.id);
    expect(refundsOf(payment)).toEqual([1_000_000_00]); // full refund
    expect((await prisma.booking.findUniqueOrThrow({ where: { id: booking.id } })).status).toBe('REFUNDED');

    await expect(payments.refundBookingBeforeMoveIn(booking.id, tenant.id)).rejects.toThrow(/already been refunded|refunded/);
    await expect(payments.adminRefundBooking(payment.id, admin.id, 'Landlord could not hand over the keys')).rejects.toThrow(/already been refunded/);
    await expect(payments.releaseBookingOnMovedIn(booking.id, tenant.id)).rejects.toBeDefined(); // can't move in on refunded money
    expect(paystack.refundCalls).toBe(1);
    expect(paystack.sent).toEqual([]);
  });

  it('a refund and a move-in at the same moment: only one of them happens', async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.delayMs = 150;
    const results = await Promise.allSettled([
      payments.releaseBookingOnMovedIn(booking.id, tenant.id),
      payments.refundBookingBeforeMoveIn(booking.id, tenant.id),
    ]);
    expect(results.filter((r) => r.status === 'fulfilled')).toHaveLength(1);
    const moneyOut = paystack.sent.length + refundsOf(payment).length;
    expect(moneyOut).toBe(1); // paid out OR refunded, never both
  });

  it('two refund requests at the same moment refund once', async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.delayMs = 150;
    await Promise.allSettled([
      payments.refundBookingBeforeMoveIn(booking.id, tenant.id),
      payments.refundBookingBeforeMoveIn(booking.id, tenant.id),
    ]);
    expect(refundsOf(payment)).toHaveLength(1);
  });

  it('an admin can retry a failed tenant refund, with the tenant\'s amount', async () => {
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.refundNext = 'rejected';
    await expect(payments.refundBookingBeforeMoveIn(booking.id, tenant.id)).rejects.toThrow(/unavailable/);
    expect((await payments.stuckPayouts())[0].requestedBy).toBe('TENANT');

    await expect(payments.retryRefund(payment.id, admin.id)).resolves.toEqual({ status: 'REFUNDED' });
    expect(refundsOf(payment)).toEqual([1_000_000_00 - 2_000_00]); // 0.2% fee kept, as the tenant asked
    await expect(payments.retryRefund(payment.id, admin.id)).resolves.toEqual({ status: 'ALREADY_REFUNDED' });
    expect(await payments.stuckPayouts()).toHaveLength(0);
  });

  it('once moved in, a tenant cannot be refunded by anyone', async () => {
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    const { tenant, booking, payment } = await awaitingMoveIn();
    paystack.next = 'rejected'; // payout fails, money still held after move-in
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    const [row] = await payments.stuckPayouts();
    expect(row.canRefundTenant).toBe(false);
    await expect(payments.adminRefundBooking(payment.id, admin.id, 'Trying to refund after move-in')).rejects.toBeInstanceOf(BadRequestException);
    await expect(payments.refundBookingBeforeMoveIn(booking.id, tenant.id)).rejects.toBeInstanceOf(BadRequestException);
    expect(paystack.refundCalls).toBe(0);
  });
});
