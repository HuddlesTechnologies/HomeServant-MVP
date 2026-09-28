import { PrismaClient, UserRole } from '@prisma/client';
import { AdminService } from '../src/admin/admin.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { PromotionsService } from '../src/promotions/promotions.service';
import { PropertiesService } from '../src/properties/properties.service';
import { rankListings, RankCandidate } from '../src/properties/listing-ranking';
import { fakeMail, fakePresence, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const day = (n: number) => new Date(Date.UTC(2026, 0, n));
const c = (id: string, n: number, extra: Partial<RankCandidate> = {}): RankCandidate => ({
  id,
  createdAt: day(n),
  available: true,
  adminBoost: 0,
  featured: false,
  ...extra,
});

describe('rankListings (fairness rules)', () => {
  it('never puts an unavailable listing above an available one, however promoted', () => {
    const order = rankListings([c('busyTop', 9, { available: false, adminBoost: 2 }), c('old', 1), c('new', 2)], 3, '2026-01-10');
    expect(order).toEqual(['new', 'old', 'busyTop']);
  });

  it('gives promoted listings only one slot in every three; the rest stay newest first', () => {
    const order = rankListings(
      [c('p1', 1, { adminBoost: 2 }), c('p2', 2, { featured: true }), c('p3', 3, { adminBoost: 1 }), c('o1', 10), c('o2', 9), c('o3', 8), c('o4', 7)],
      3,
      '2026-01-10',
    );
    expect(order[0]).toBe('p1'); // top beats boosted/featured
    expect(order.slice(1, 3)).toEqual(['o1', 'o2']);
    expect(order.slice(4, 6)).toEqual(['o3', 'o4']);
    expect(new Set([order[3], order[6]])).toEqual(new Set(['p2', 'p3']));
  });

  it('rotates equally promoted listings from day to day', () => {
    const promoted = Array.from({ length: 8 }, (_, i) => c(`p${i}`, i + 1, { featured: true }));
    const firsts = new Set(['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04', '2026-01-05'].map((d) => rankListings(promoted, 3, d)[0]));
    expect(firsts.size).toBeGreaterThan(1);
  });
});

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('featured ads and admin ranking (real Postgres)', () => {
  let prisma: PrismaClient;
  let properties: PropertiesService;
  let promotions: PromotionsService;
  let settings: PlatformSettingsService;
  let admin: AdminService;
  let initialized: { reference: string; amount: number }[];

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    initialized = [];
    const notifier = { create: async () => undefined };
    settings = new PlatformSettingsService(prisma as never, notifier as never, fakeMail() as never);
    properties = new PropertiesService(prisma as never, { summaryForProperties: async () => new Map() } as never, {} as never, settings, notifier as never);
    const paystack = {
      async initializeTransaction(_email: string, amount: number, reference: string) {
        initialized.push({ reference, amount });
        return { reference, authorizationUrl: `https://pay/${reference}` };
      },
    };
    promotions = new PromotionsService(prisma as never, paystack as never, settings, notifier as never);
    admin = new AdminService(prisma as never, {} as never, {} as never, {} as never, {} as never, { log: async () => undefined } as never, fakePresence(new Set()) as never, {} as never, {} as never);
  });

  it('charges the Platform Controls fee, features the listing once paid, and extends a running ad', async () => {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const listing = await makeProperty(prisma, landlord.id);
    const superAdmin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    await settings.update(superAdmin.id, { featuredListingFeeNaira: 8000, featuredListingDays: 10 });

    const checkout = await promotions.start(listing.id, landlord.id);
    expect(initialized).toEqual([{ reference: checkout.reference, amount: 800_000 }]);
    expect((await properties.findOne(listing.id)).featured).toBe(false);

    expect(await promotions.handleChargeSuccess(checkout.reference)).toBe(true);
    expect(await promotions.handleChargeSuccess(checkout.reference)).toBe(true); // retry is a no-op
    const shown = await properties.findOne(listing.id);
    expect(shown.featured).toBe(true);
    const firstEnd = shown.featuredUntil!.getTime();
    expect(firstEnd).toBeGreaterThan(Date.now() + 9.9 * 86_400_000);

    const again = await promotions.start(listing.id, landlord.id);
    await promotions.handleChargeSuccess(again.reference);
    expect((await properties.findOne(listing.id)).featuredUntil!.getTime()).toBeCloseTo(firstEnd + 10 * 86_400_000, -3);

    // Not a featured-ad reference: left to rent/order handling.
    expect(await promotions.handleChargeSuccess('rent_123')).toBe(false);
  });

  it("won't feature a hidden listing or someone else's", async () => {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const other = await makeUser(prisma, UserRole.LANDLORD);
    const listing = await makeProperty(prisma, landlord.id);
    await expect(promotions.start(listing.id, other.id)).rejects.toThrow(/do not own/);
    await prisma.property.update({ where: { id: listing.id }, data: { hiddenByLandlordAt: new Date() } });
    await expect(promotions.start(listing.id, landlord.id)).rejects.toThrow(/Show this listing/);
  });

  it('puts an admin-boosted available shortlet first, but a booked-out one after available listings', async () => {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const moderator = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
    const older = await makeProperty(prisma, landlord.id, { category: 'SHORTLET' });
    const popular = await makeProperty(prisma, landlord.id, { category: 'SHORTLET' });
    await prisma.property.update({ where: { id: popular.id }, data: { createdAt: new Date(Date.now() - 86_400_000) } });
    await prisma.property.update({ where: { id: older.id }, data: { createdAt: new Date(Date.now() - 2 * 86_400_000) } });
    const newest = await makeProperty(prisma, landlord.id, { category: 'SHORTLET' });

    await admin.setPropertyBoost(popular.id, 2, 30, 'Consistently well reviewed', moderator.id);
    expect((await properties.findMany({})).items.map((p) => p.id)).toEqual([popular.id, newest.id, older.id]);

    // Booked out right now: it drops below every bookable shortlet.
    await prisma.booking.create({
      data: {
        tenantId: tenant.id,
        propertyId: popular.id,
        status: 'PAID',
        leaseStartDate: new Date(Date.now() - 3_600_000),
        leaseEndDate: new Date(Date.now() + 86_400_000),
      },
    });
    const ranked = await properties.findMany({});
    expect(ranked.items.map((p) => p.id)).toEqual([newest.id, older.id, popular.id]);
    expect(ranked.total).toBe(3);
  });
});
