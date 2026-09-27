import { ConflictException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { PaymentsService } from '../src/payments/payments.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { PropertiesService } from '../src/properties/properties.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;
const DAY = 86_400_000;

describeDb('landlord rent changes (real Postgres)', () => {
  let prisma: PrismaClient;
  let notes: { userId: string; title: string; body: string }[];
  let payments: PaymentsService;
  let properties: PropertiesService;
  let initialized: { reference: string; amount: number }[];

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
      async initiateTransfer() {},
    };
    const chat = { postBookingSystemMessage: async () => undefined };
    payments = new PaymentsService(prisma as never, paystack as never, notifier as never, mail as never, chat as never, settings);
    properties = new PropertiesService(prisma as never, {} as never, { assertIsOwnImage: async () => undefined } as never, settings, notifier as never);
  });

  /// A tenant in the last weeks of a ₦1,000,000/year, 12-month lease.
  async function currentLease() {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    await prisma.user.update({ where: { id: landlord.id }, data: { bankCode: '058', accountNumber: '0123456789', accountName: 'Test Landlord' } });
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const property = await makeProperty(prisma, landlord.id, { isOccupied: true });
    await prisma.property.update({ where: { id: property.id }, data: { price: 1_000_000, priceUnit: 'YEAR', rentDurationMonths: 12 } });
    const leaseEnd = new Date(Date.now() + 10 * DAY);
    const booking = await prisma.booking.create({
      data: {
        propertyId: property.id,
        tenantId: tenant.id,
        status: 'MOVED_IN',
        leaseStartDate: new Date(leaseEnd.getTime() - 365 * DAY),
        leaseEndDate: leaseEnd,
        priceSnapshot: 1_000_000,
        priceUnitSnapshot: 'YEAR',
      },
    });
    await prisma.tenancyAgreement.create({
      data: {
        bookingId: booking.id,
        propertyTitle: property.title,
        propertyLocation: 'Lekki',
        propertyState: 'Lagos',
        rentAmount: 1_000_000,
        priceUnit: 'YEAR',
        leaseStartDate: booking.leaseStartDate!,
        leaseEndDate: leaseEnd,
        landlordName: 'L',
        landlordEmail: landlord.email,
        tenantName: 'T',
        tenantEmail: tenant.email,
      },
    });
    return { landlord, tenant, property, booking, leaseEnd };
  }

  it('tells tenants with a live booking when the rent changes, and what it means for them', async () => {
    const { landlord, tenant, property } = await currentLease();
    const unpaid = await makeUser(prisma, UserRole.TENANT);
    await prisma.booking.create({ data: { propertyId: property.id, tenantId: unpaid.id, status: 'PENDING' } });
    const pastTenant = await makeUser(prisma, UserRole.TENANT);
    await prisma.booking.create({ data: { propertyId: property.id, tenantId: pastTenant.id, status: 'REFUNDED' } });

    await properties.update(property.id, landlord.id, { title: 'New title only' });
    expect(notes).toEqual([]); // nothing about the rent changed

    await properties.update(property.id, landlord.id, { price: 1_200_000 });
    const byUser = new Map(notes.map((n) => [n.userId, n]));
    expect(byUser.size).toBe(2);
    expect(byUser.get(tenant.id)!.title).toBe('Rent changed');
    expect(byUser.get(tenant.id)!.body).toContain('from ₦1,000,000/year to ₦1,200,000/year');
    expect(byUser.get(tenant.id)!.body).toContain('The new terms apply if you renew');
    expect(byUser.get(unpaid.id)!.body).toContain("you'll pay the new price");
    expect(byUser.has(pastTenant.id)).toBe(false);
  });

  it('quotes the renewal, refuses a changed amount, and updates the agreement to the rent actually paid', async () => {
    const { landlord, tenant, property, booking, leaseEnd } = await currentLease();
    await properties.update(property.id, landlord.id, { price: 1_200_000 });

    const quote = await payments.renewalQuote(booking.id, tenant.id);
    expect(quote).toMatchObject({ amount: 1_200_000, priceUnit: 'YEAR', leaseMonths: 12, previousAmount: 1_000_000 });

    // The tenant saw ₦1,200,000; the landlord raises it again before they pay.
    await properties.update(property.id, landlord.id, { price: 1_300_000 });
    await expect(payments.renewBooking(booking.id, tenant.id, { amount: quote.amount, leaseMonths: quote.leaseMonths })).rejects.toBeInstanceOf(
      ConflictException,
    );
    expect(initialized).toEqual([]); // nothing was charged

    const fresh = await payments.renewalQuote(booking.id, tenant.id);
    const charge = await payments.renewBooking(booking.id, tenant.id, { amount: fresh.amount, leaseMonths: fresh.leaseMonths });
    expect(initialized).toEqual([{ reference: charge.reference, amount: 1_300_000_00 }]);
    // Until the renewal is paid, the booking still shows the rent last paid.
    expect((await prisma.booking.findUniqueOrThrow({ where: { id: booking.id } })).priceSnapshot).toBe(1_000_000);

    await payments.handleChargeSuccess(charge.reference);
    const renewed = await prisma.booking.findUniqueOrThrow({ where: { id: booking.id }, include: { tenancyAgreement: true } });
    expect(renewed.priceSnapshot).toBe(1_300_000);
    expect(renewed.leaseEndDate!.getTime()).toBeGreaterThan(leaseEnd.getTime() + 360 * DAY);
    expect(renewed.tenancyAgreement!.rentAmount).toBe(1_300_000);
    expect(renewed.tenancyAgreement!.leaseEndDate.getTime()).toBe(renewed.leaseEndDate!.getTime());
    expect(notes.some((n) => n.userId === tenant.id && n.title === 'Lease renewed' && n.body.includes('₦1,300,000/year'))).toBe(true);
  });

  it('an abandoned renewal leaves the booking and agreement on the rent last paid', async () => {
    const { landlord, tenant, property, booking } = await currentLease();
    await properties.update(property.id, landlord.id, { price: 1_500_000 });
    await payments.renewBooking(booking.id, tenant.id); // older app: no expected amount; charged the current price
    expect(initialized[0].amount).toBe(1_500_000_00);
    const after = await prisma.booking.findUniqueOrThrow({ where: { id: booking.id }, include: { tenancyAgreement: true } });
    expect(after.priceSnapshot).toBe(1_000_000);
    expect(after.tenancyAgreement!.rentAmount).toBe(1_000_000);
  });
});
