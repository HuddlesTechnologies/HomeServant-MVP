import { ForbiddenException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { BookingsService } from '../src/bookings/bookings.service';
import { FavoritesService } from '../src/favorites/favorites.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { PropertiesService } from '../src/properties/properties.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('platform controls: only verified landlords (real Postgres)', () => {
  let prisma: PrismaClient;
  let settings: PlatformSettingsService;
  let properties: PropertiesService;
  let bookings: BookingsService;
  let favorites: FavoritesService;
  let notes: { userId: string; title: string }[];
  let mail: ReturnType<typeof fakeMail>;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    notes = [];
    mail = fakeMail();
    const notifier = { create: async (userId: string, _t: unknown, title: string) => void notes.push({ userId, title }) };
    settings = new PlatformSettingsService(prisma as never, notifier as never, mail as never);
    favorites = new FavoritesService(prisma as never, settings);
    const reviews = { summaryForProperties: async () => new Map() };
    properties = new PropertiesService(prisma as never, reviews as never, {} as never, settings, { create: async () => undefined } as never);
    const notifications = { create: async () => undefined };
    const payments = { chargeBooking: async () => ({ reference: 'r', authorizationUrl: 'https://pay' }) };
    bookings = new BookingsService(prisma as never, notifications as never, payments as never, settings, { postBookingSystemMessage: async () => null } as never);
  });

  async function setup() {
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    const verified = await makeUser(prisma, UserRole.LANDLORD);
    const unverified = await makeUser(prisma, UserRole.LANDLORD);
    await prisma.identityVerification.create({ data: { userId: verified.id, status: 'APPROVED', idType: 'NIN', idNumber: '12345678901' } });
    await prisma.identityVerification.create({ data: { userId: unverified.id, status: 'PENDING', idType: 'NIN', idNumber: '12345678902' } });
    const good = await makeProperty(prisma, verified.id, { category: 'SHORTLET' });
    const hidden = await makeProperty(prisma, unverified.id, { category: 'SHORTLET' });
    return { admin, verified, unverified, good, hidden };
  }

  it('off by default: everything is listed, each with its landlordVerified flag', async () => {
    const { good, hidden } = await setup();
    const { items } = await properties.findMany({});
    expect(items.map((p) => p.id).sort()).toEqual([good.id, hidden.id].sort());
    expect(items.find((p) => p.id === good.id)!.landlordVerified).toBe(true);
    expect(items.find((p) => p.id === hidden.id)!.landlordVerified).toBe(false);
    expect((await settings.get()).requireVerifiedLandlords).toBe(false);
  });

  it('on: browsing hides unverified landlords, owners still see theirs, and booking is refused', async () => {
    const { admin, unverified, good, hidden } = await setup();
    const saved = await settings.update(admin.id, { requireVerifiedLandlords: true });
    expect(saved.updatedBy!.id).toBe(admin.id);

    expect((await properties.findMany({})).items.map((p) => p.id)).toEqual([good.id]);
    expect((await properties.findMany({ landlordId: unverified.id })).items.map((p) => p.id)).toEqual([hidden.id]);

    const tenant = await makeUser(prisma, UserRole.TENANT);
    const dto = { propertyId: hidden.id, requestedDate: new Date(Date.now() + 86_400_000).toISOString(), nights: 2 };
    await expect(bookings.create(tenant.id, dto as never)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(bookings.create(tenant.id, { ...dto, propertyId: good.id } as never)).resolves.toBeDefined();
  });

  it("tenants who already booked or saved a hidden listing can see why it's hidden", async () => {
    const { admin, good, hidden } = await setup();
    const tenant = await makeUser(prisma, UserRole.TENANT);
    await prisma.booking.create({ data: { propertyId: hidden.id, tenantId: tenant.id, status: 'PAID_AWAITING_INSPECTION' } });
    await prisma.favorite.create({ data: { userId: tenant.id, propertyId: hidden.id } });

    // Off: nothing is hidden.
    expect((await bookings.findForTenant(tenant.id))[0].property.hiddenUntilLandlordVerified).toBe(false);

    await settings.update(admin.id, { requireVerifiedLandlords: true });
    const [booking] = await bookings.findForTenant(tenant.id);
    expect(booking.status).toBe('PAID_AWAITING_INSPECTION'); // the booking itself is untouched
    expect(booking.property.hiddenUntilLandlordVerified).toBe(true);
    expect(booking.property.landlordVerified).toBe(false);
    expect((await favorites.findForUser(tenant.id))[0].property.hiddenUntilLandlordVerified).toBe(true);
    expect((await properties.findOne(hidden.id)).hiddenUntilLandlordVerified).toBe(true);
    expect((await properties.findOne(good.id)).hiddenUntilLandlordVerified).toBe(false);
  });

  it('switching it on tells each unverified landlord with listings, once', async () => {
    const { admin, verified, unverified } = await setup();
    await makeUser(prisma, UserRole.LANDLORD); // no listings: not told
    await settings.update(admin.id, { requireVerifiedLandlords: true });
    await new Promise((r) => setTimeout(r, 200)); // runs in the background
    expect(notes.map((n) => n.userId)).toEqual([unverified.id]);
    expect(mail.sent.map((m) => m.to)).toEqual([unverified.email]);
    expect(notes.some((n) => n.userId === verified.id)).toBe(false);

    await settings.update(admin.id, { requireVerifiedLandlords: true }); // already on: no repeat
    await new Promise((r) => setTimeout(r, 200));
    expect(notes).toHaveLength(1);
  });
});
