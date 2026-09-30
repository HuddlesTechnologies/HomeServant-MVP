import { PrismaClient, UserRole } from '@prisma/client';
import { PaymentsService } from '../src/payments/payments.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('admin pausing and cancelling a payout (real Postgres)', () => {
  let prisma: PrismaClient;
  let settings: PlatformSettingsService;
  let payments: PaymentsService;
  let transfers: string[];
  let notes: { userId: string; title: string; body: string }[];

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    transfers = [];
    notes = [];
    const notifier = {
      create: async (userId: string, _t: unknown, title: string, body: string) => void notes.push({ userId, title, body }),
    };
    const mail = fakeMail();
    settings = new PlatformSettingsService(prisma as never, notifier as never, mail as never);
    const paystack = {
      createTransferRecipient: async () => 'RCP_1',
      verifyTransfer: async (reference: string) => (transfers.includes(reference) ? 'success' : 'not_found'),
      initiateTransfer: async (_amount: number, _code: string, _reason: string, reference: string) => void transfers.push(reference),
      balanceKobo: async () => 10_000_000_00,
    };
    const chat = { postBookingSystemMessage: async () => undefined };
    payments = new PaymentsService(prisma as never, paystack as never, notifier as never, mail as never, chat as never, settings);
  });

  /// A rental whose inspection is confirmed, with the tenant's money held.
  async function awaitingMoveIn() {
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
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
      },
    });
    return { admin, landlord, tenant, booking, payment };
  }

  it('a paused payout is not sent on move-in, is listed as paused, and goes out on resume', async () => {
    const { admin, landlord, tenant, booking, payment } = await awaitingMoveIn();
    await payments.pausePayout(payment.id, admin.id, 'Checking a complaint');

    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect((await prisma.booking.findUniqueOrThrow({ where: { id: booking.id } })).status).toBe('MOVED_IN');
    expect(transfers).toEqual([]);
    expect(notes.find((n) => n.userId === landlord.id && n.title === 'Tenant moved in')!.body).toMatch(/paused your payout/);

    const [row] = await payments.stuckPayouts();
    expect(row).toMatchObject({ paymentId: payment.id, reason: 'PAUSED', canRetry: false, canResume: true, pauseReason: 'Checking a complaint' });
    await expect(payments.retryPayout(payment.id)).rejects.toThrow(/paused/);

    const resumed = await payments.resumePayout(payment.id, admin.id);
    expect(resumed.sent).toBe(true);
    expect(transfers).toEqual([payment.id]);
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).status).toBe('RELEASED');
  });

  it('a paused payout held for verification is not released when the landlord is verified', async () => {
    const { admin, landlord, tenant, booking, payment } = await awaitingMoveIn();
    await settings.update(admin.id, { payUnverifiedLandlords: false });
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    await payments.pausePayout(payment.id, admin.id, '');
    await prisma.identityVerification.create({ data: { userId: landlord.id, status: 'APPROVED', idType: 'NIN', idNumber: '12345678901' } });
    expect(await payments.releaseHeldPayoutsForLandlord(landlord.id)).toBe(0);
    expect(transfers).toEqual([]);
  });

  it('a cancelled payout is never sent, leaves the list, and the landlord is told why', async () => {
    const { admin, landlord, tenant, booking, payment } = await awaitingMoveIn();
    await settings.update(admin.id, { payUnverifiedLandlords: false });
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect(await payments.stuckPayoutCount()).toBe(1);

    await expect(payments.cancelPayout(payment.id, admin.id, 'short')).rejects.toThrow(/reason/);
    await payments.cancelPayout(payment.id, admin.id, 'Listing found to be fraudulent');
    expect(await payments.stuckPayoutCount()).toBe(0);
    expect(notes.find((n) => n.userId === landlord.id && n.title === 'Your payout was cancelled')!.body).toMatch(/fraudulent/);

    await prisma.identityVerification.create({ data: { userId: landlord.id, status: 'APPROVED', idType: 'NIN', idNumber: '12345678901' } });
    expect(await payments.releaseHeldPayoutsForLandlord(landlord.id)).toBe(0);
    await expect(payments.retryPayout(payment.id)).rejects.toThrow(/cancelled/);
    expect(transfers).toEqual([]);
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).status).toBe('PAID_HELD');
  });
});
