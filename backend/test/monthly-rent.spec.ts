import { BadRequestException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { BookingsService } from '../src/bookings/bookings.service';
import { LeaseLifecycleService } from '../src/bookings/lease-lifecycle.service';
import { PaymentsService } from '../src/payments/payments.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;
const DAY = 86_400_000;

describeDb('monthly rent (real Postgres)', () => {
  let prisma: PrismaClient;
  let notes: { userId: string; title: string; body: string }[];
  let initialized: { reference: string; amount: number }[];
  let transfers: number;
  let payments: PaymentsService;
  let bookings: BookingsService;
  let lifecycle: LeaseLifecycleService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    notes = [];
    initialized = [];
    transfers = 0;
    const notifier = { create: async (userId: string, _t: unknown, title: string, body: string) => void notes.push({ userId, title, body }) };
    const mail = fakeMail();
    const settings = new PlatformSettingsService(prisma as never, notifier as never, mail as never);
    const paystack = {
      async initializeTransaction(_email: string, amount: number, reference: string) {
        initialized.push({ reference, amount });
        return { reference, authorizationUrl: `https://pay/${reference}` };
      },
      async createTransferRecipient() {
        return 'RCP_1';
      },
      async verifyTransfer() {
        return 'not_found';
      },
      async initiateTransfer() {
        transfers++;
      },
    };
    const chat = { postBookingSystemMessage: async () => undefined };
    payments = new PaymentsService(prisma as never, paystack as never, notifier as never, mail as never, chat as never, settings);
    bookings = new BookingsService(prisma as never, notifier as never, payments, settings);
    lifecycle = new LeaseLifecycleService(prisma as never, notifier as never, mail as never);
  });

  /// ₦1,200,000/year, 12-month lease; monthly allowed unless said otherwise.
  async function listing(allowMonthlyPayment = true) {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    await prisma.user.update({
      where: { id: landlord.id },
      data: { bankCode: '058', accountNumber: '0123456789', accountName: 'Test Landlord' },
    });
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const property = await makeProperty(prisma, landlord.id);
    await prisma.property.update({
      where: { id: property.id },
      data: { price: 1_200_000, priceUnit: 'YEAR', rentDurationMonths: 12, allowMonthlyPayment },
    });
    return { landlord, tenant, property };
  }

  it("refuses a monthly plan the landlord hasn't allowed", async () => {
    const { tenant, property } = await listing(false);
    await expect(bookings.create(tenant.id, { propertyId: property.id, paymentPlan: 'MONTHLY' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('charges one month up front, then month by month, reminding and flagging a missed month', async () => {
    const { landlord, tenant, property } = await listing();

    // First month: ₦100,000, held in escrow until move-in like a full payment.
    const created = (await bookings.create(tenant.id, { propertyId: property.id, paymentPlan: 'MONTHLY' })) as unknown as { id: string; reference: string };
    expect(initialized).toEqual([{ reference: created.reference, amount: 100_000_00 }]);
    await payments.handleChargeSuccess(created.reference);
    let booking = await prisma.booking.findUniqueOrThrow({ where: { id: created.id } });
    expect(booking).toMatchObject({ status: 'PAID_AWAITING_INSPECTION', paymentPlan: 'MONTHLY', monthlyRent: 100_000 });
    expect(transfers).toBe(0);

    await prisma.booking.update({ where: { id: created.id }, data: { status: 'INSPECTION_CONFIRMED' } });
    await payments.releaseBookingOnMovedIn(created.id, tenant.id);
    booking = await prisma.booking.findUniqueOrThrow({ where: { id: created.id } });
    expect(transfers).toBe(1);
    const firstPaidThrough = booking.rentPaidThrough!;
    expect(firstPaidThrough.getTime()).toBeGreaterThan(Date.now() + 27 * DAY);
    expect(firstPaidThrough.getTime()).toBeLessThan(Date.now() + 32 * DAY);

    // Too early to pay next month; renewing isn't possible with months unpaid.
    await expect(payments.payMonthlyRent(created.id, tenant.id)).rejects.toThrow(/from 7 days before/);

    // Three days out: the tenant is reminded once.
    const inThreeDays = new Date(Date.now() + 2.5 * DAY);
    await prisma.booking.update({ where: { id: created.id }, data: { rentPaidThrough: inThreeDays } });
    await lifecycle.sendMonthlyRentReminders();
    await lifecycle.sendMonthlyRentReminders();
    expect(notes.filter((n) => n.title === 'Monthly rent due soon').map((n) => n.userId)).toEqual([tenant.id]);

    // It goes overdue: tenant told, landlord flagged — once.
    const overdue = new Date(Date.now() - DAY);
    await prisma.booking.update({ where: { id: created.id }, data: { rentPaidThrough: overdue } });
    await lifecycle.sendMonthlyRentReminders();
    await lifecycle.sendMonthlyRentReminders();
    expect(notes.filter((n) => n.title === 'Monthly rent overdue').map((n) => n.userId)).toEqual([tenant.id]);
    expect(notes.filter((n) => n.title === 'Tenant missed a monthly payment').map((n) => n.userId)).toEqual([landlord.id]);

    // Paying it: the month goes straight to the landlord, a month further on.
    const month = await payments.payMonthlyRent(created.id, tenant.id);
    expect(initialized[1]).toEqual({ reference: month.reference, amount: 100_000_00 });
    await payments.handleChargeSuccess(month.reference);
    booking = await prisma.booking.findUniqueOrThrow({ where: { id: created.id } });
    expect(transfers).toBe(2);
    expect(booking.rentPaidThrough!.getTime()).toBeGreaterThan(overdue.getTime() + 27 * DAY);
    expect(booking.monthlyOverdueNotifiedFor).toBeNull();
    expect(booking.priceSnapshot).toBe(1_200_000); // the lease's rent is still the yearly price
    expect(notes.some((n) => n.userId === landlord.id && n.title === 'Monthly rent received')).toBe(true);

    // Renewing needs every month paid.
    await prisma.booking.update({
      where: { id: created.id },
      data: { rentPaidThrough: new Date(Date.now() + 5 * DAY), leaseEndDate: new Date(Date.now() + 20 * DAY) },
    });
    await expect(payments.renewBooking(created.id, tenant.id)).rejects.toThrow(/remaining months/);
  });
});
