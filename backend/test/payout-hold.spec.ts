import { PrismaClient, UserRole } from '@prisma/client';
import { PaymentsService } from '../src/payments/payments.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('payout hold for unverified landlords (real Postgres)', () => {
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

  it('by default an unverified landlord is paid on move-in as before', async () => {
    const { tenant, booking, payment } = await awaitingMoveIn();
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect(transfers).toEqual([payment.id]);
    expect((await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } })).status).toBe('RELEASED');
  });

  it('when switched off: the tenant still moves in, the payout is held, then released on verification', async () => {
    const { admin, landlord, tenant, booking, payment } = await awaitingMoveIn();
    await settings.update(admin.id, { payUnverifiedLandlords: false });

    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect((await prisma.booking.findUniqueOrThrow({ where: { id: booking.id } })).status).toBe('MOVED_IN');
    const held = await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
    expect(held.status).toBe('PAID_HELD');
    expect(held.heldForVerificationAt).not.toBeNull();
    expect(transfers).toEqual([]);
    expect(notes.find((n) => n.userId === landlord.id && n.title === 'Tenant moved in')!.body).toMatch(/holding your payout/);
    expect((await payments.heldPayoutStats()).count).toBe(1);

    await prisma.identityVerification.create({ data: { userId: landlord.id, status: 'APPROVED', idType: 'NIN', idNumber: '12345678901' } });
    expect(await payments.releaseHeldPayoutsForLandlord(landlord.id)).toBe(1);
    const released = await prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
    expect(released.status).toBe('RELEASED');
    expect(released.heldForVerificationAt).toBeNull();
    expect(transfers).toEqual([payment.id]);
    expect((await payments.heldPayoutStats()).count).toBe(0);
  });

  it('a verified landlord is paid even when the rule is off', async () => {
    const { admin, landlord, tenant, booking, payment } = await awaitingMoveIn();
    await prisma.identityVerification.create({ data: { userId: landlord.id, status: 'APPROVED', idType: 'NIN', idNumber: '12345678901' } });
    await settings.update(admin.id, { payUnverifiedLandlords: false });
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect(transfers).toEqual([payment.id]);
  });

  it('switching payments back on releases everything held', async () => {
    const { admin, tenant, booking, payment } = await awaitingMoveIn();
    await settings.update(admin.id, { payUnverifiedLandlords: false });
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect(transfers).toEqual([]);
    expect(await payments.releaseAllHeldPayouts()).toBe(1);
    expect(transfers).toEqual([payment.id]);
  });
});
