import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { BookingsService } from '../src/bookings/bookings.service';
import { PaymentsService } from '../src/payments/payments.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { PropertiesService } from '../src/properties/properties.service';
import { ReviewsService } from '../src/reviews/reviews.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('one booking per property, and rating after payout (real Postgres)', () => {
  let prisma: PrismaClient;
  let initialized: string[];
  let paidAtPaystack: Set<string>;
  let payments: PaymentsService;
  let bookings: BookingsService;
  let reviews: ReviewsService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    initialized = [];
    paidAtPaystack = new Set();
    const notifier = { create: async () => undefined };
    const mail = fakeMail();
    const settings = new PlatformSettingsService(prisma as never, notifier as never, mail as never);
    const paystack = {
      async initializeTransaction(_email: string, _amount: number, reference: string) {
        initialized.push(reference);
        return { reference, authorizationUrl: `https://pay/${reference}` };
      },
      async verifyCharge(reference: string) {
        return paidAtPaystack.has(reference) ? 'success' : 'abandoned';
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
    bookings = new BookingsService(prisma as never, notifier as never, payments, settings, { postBookingSystemMessage: async () => null } as never);
    reviews = new ReviewsService(prisma as never);
  });

  async function listing() {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    await prisma.user.update({
      where: { id: landlord.id },
      data: { bankCode: '058', accountNumber: '0123456789', accountName: 'Test Landlord' },
    });
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const property = await makeProperty(prisma, landlord.id);
    await prisma.property.update({ where: { id: property.id }, data: { rentDurationMonths: 12 } });
    return { tenant, property };
  }

  type Created = { id: string; reference: string };

  it('refuses Rent Now once the property is paid for', async () => {
    const { tenant, property } = await listing();
    const first = (await bookings.create(tenant.id, { propertyId: property.id })) as unknown as Created;
    await payments.handleChargeSuccess(first.reference);

    await expect(bookings.create(tenant.id, { propertyId: property.id })).rejects.toBeInstanceOf(BadRequestException);
    expect(await prisma.booking.count()).toBe(1);
  });

  it('reuses an unfinished checkout instead of creating a second booking', async () => {
    const { tenant, property } = await listing();
    const first = (await bookings.create(tenant.id, { propertyId: property.id })) as unknown as Created;
    const again = (await bookings.create(tenant.id, { propertyId: property.id })) as unknown as Created;

    expect(again.id).toBe(first.id);
    expect(again.reference).not.toBe(first.reference);
    expect(await prisma.booking.count()).toBe(1);
    expect(await bookings.findForTenant(tenant.id)).toHaveLength(1);
  });

  it("confirms a checkout that was paid but whose webhook hasn't arrived, instead of charging again", async () => {
    const { tenant, property } = await listing();
    const first = (await bookings.create(tenant.id, { propertyId: property.id })) as unknown as Created;
    paidAtPaystack.add(first.reference);

    await expect(bookings.create(tenant.id, { propertyId: property.id })).rejects.toBeInstanceOf(BadRequestException);
    expect(initialized).toEqual([first.reference]);
    const booking = await prisma.booking.findUniqueOrThrow({ where: { id: first.id } });
    expect(booking.status).toBe('PAID_AWAITING_INSPECTION');
    // The webhook arriving afterwards changes nothing.
    await payments.handleChargeSuccess(first.reference);
    expect(await prisma.payment.count({ where: { status: 'PAID_HELD' } })).toBe(1);
  });

  it('confirm-payment marks the booking paid when the tenant returns from Paystack', async () => {
    const { tenant, property } = await listing();
    const first = (await bookings.create(tenant.id, { propertyId: property.id })) as unknown as Created;
    expect(await bookings.confirmPayment(first.reference, tenant.id)).toEqual({ paid: false });

    paidAtPaystack.add(first.reference);
    expect(await bookings.confirmPayment(first.reference, tenant.id)).toEqual({ paid: true });
    const booking = await prisma.booking.findUniqueOrThrow({ where: { id: first.id } });
    expect(booking.status).toBe('PAID_AWAITING_INSPECTION');

    const stranger = await makeUser(prisma, UserRole.TENANT);
    await expect(bookings.confirmPayment(first.reference, stranger.id)).rejects.toThrow('Payment not found');
  });

  it('hides duplicate unpaid bookings left behind by older app versions', async () => {
    const { tenant, property } = await listing();
    const paid = (await bookings.create(tenant.id, { propertyId: property.id })) as unknown as Created;
    await payments.handleChargeSuccess(paid.reference);
    // What the old Rent Now left behind: a second, never-paid booking.
    await prisma.booking.create({ data: { propertyId: property.id, tenantId: tenant.id } });

    const history = await bookings.findForTenant(tenant.id);
    expect(history.map((b) => b.id)).toEqual([paid.id]);
  });

  it('hides a rental from browsing once paid for, and refuses a second tenant', async () => {
    const { tenant, property } = await listing();
    const notifier = { create: async () => undefined };
    const settings = new PlatformSettingsService(prisma as never, notifier as never, fakeMail() as never);
    const properties = new PropertiesService(prisma as never, reviews, {} as never, settings, notifier as never);
    const browse = async () => (await properties.findMany({})).items.map((p) => p.id);
    expect(await browse()).toEqual([property.id]);

    // Rent Now pressed but never paid: still listed.
    const booking = (await bookings.create(tenant.id, { propertyId: property.id })) as unknown as Created;
    expect(await browse()).toEqual([property.id]);

    await payments.handleChargeSuccess(booking.reference);
    expect(await browse()).toEqual([]);
    const other = await makeUser(prisma, UserRole.TENANT);
    await expect(bookings.create(other.id, { propertyId: property.id })).rejects.toThrow('already been rented');
    // The tenant who paid can still open it directly.
    await expect(properties.findOne(property.id)).resolves.toMatchObject({ id: property.id });

    // Moved in: still hidden. Refunded instead: listed again.
    await prisma.booking.update({ where: { id: booking.id }, data: { status: 'INSPECTION_CONFIRMED' } });
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);
    expect(await browse()).toEqual([]);
    await prisma.booking.update({ where: { id: booking.id }, data: { status: 'REFUNDED' } });
    await prisma.property.update({ where: { id: property.id }, data: { isOccupied: false } });
    expect(await browse()).toEqual([property.id]);
  });

  it('only lets a tenant rate once the landlord has been paid', async () => {
    const { tenant, property } = await listing();
    const booking = (await bookings.create(tenant.id, { propertyId: property.id })) as unknown as Created;
    await payments.handleChargeSuccess(booking.reference);

    await expect(reviews.upsert(tenant.id, { propertyId: property.id, rating: 5 })).rejects.toBeInstanceOf(ForbiddenException);
    expect((await bookings.findForTenant(tenant.id))[0].landlordPaid).toBe(false);

    await prisma.booking.update({ where: { id: booking.id }, data: { status: 'INSPECTION_CONFIRMED' } });
    await payments.releaseBookingOnMovedIn(booking.id, tenant.id);

    expect((await bookings.findForTenant(tenant.id))[0].landlordPaid).toBe(true);
    await expect(reviews.upsert(tenant.id, { propertyId: property.id, rating: 5 })).resolves.toMatchObject({ rating: 5 });
  });
});
