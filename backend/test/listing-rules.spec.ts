import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { BookingsService } from '../src/bookings/bookings.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { PropertiesService } from '../src/properties/properties.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;
const DAY = 86_400_000;

describeDb('landlord listing rules: photo changes and hiding (real Postgres)', () => {
  let prisma: PrismaClient;
  let properties: PropertiesService;
  let settings: PlatformSettingsService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    const notifier = { create: async () => undefined };
    settings = new PlatformSettingsService(prisma as never, notifier as never, fakeMail() as never);
    const storage = { assertIsOwnImage: async () => undefined, assertAreOwnImages: async () => undefined };
    const reviews = { summaryForProperties: async () => new Map() };
    properties = new PropertiesService(prisma as never, reviews as never, storage as never, settings, notifier as never);
  });

  async function listing() {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const property = await makeProperty(prisma, landlord.id);
    return { landlord, property };
  }

  it('allows 3 photo changes, then locks the photos for 14 days, then starts a fresh allowance', async () => {
    const { landlord, property } = await listing();
    for (let n = 1; n <= 3; n++) {
      const updated = await properties.update(property.id, landlord.id, { imageUrl: `https://img/${n}.jpg` });
      expect(updated.imageChangesLeft).toBe(3 - n);
    }
    const locked = await prisma.property.findUniqueOrThrow({ where: { id: property.id } });
    expect(locked.imagesLockedUntil!.getTime()).toBeGreaterThan(Date.now() + 13.9 * DAY);

    await expect(properties.update(property.id, landlord.id, { galleryUrls: ['https://img/x.jpg'] })).rejects.toThrow(
      /used all 3 photo changes/,
    );
    // Other edits still go through while the photos are locked…
    await properties.update(property.id, landlord.id, { title: 'Renamed', imageUrl: 'https://img/3.jpg' });
    expect((await prisma.property.findUniqueOrThrow({ where: { id: property.id } })).title).toBe('Renamed');

    // …and once the lock has passed, a fresh allowance starts.
    await prisma.property.update({ where: { id: property.id }, data: { imagesLockedUntil: new Date(Date.now() - 1000) } });
    const fresh = await properties.update(property.id, landlord.id, { imageUrl: 'https://img/4.jpg' });
    expect(fresh.imageChangesLeft).toBe(2);
    expect(fresh.imagesLockedUntil).toBeNull();
  });

  it('uses the limits set in Platform Controls', async () => {
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    await settings.update(admin.id, { maxListingImageChanges: 1, listingImageLockDays: 7 });
    const { landlord, property } = await listing();
    await properties.update(property.id, landlord.id, { imageUrl: 'https://img/1.jpg' });
    const row = await prisma.property.findUniqueOrThrow({ where: { id: property.id } });
    expect(row.imagesLockedUntil!.getTime()).toBeLessThan(Date.now() + 7.1 * DAY);
    await expect(properties.update(property.id, landlord.id, { imageUrl: 'https://img/2.jpg' })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('hides an unoccupied listing from search and booking, but not from its landlord', async () => {
    const { landlord, property } = await listing();
    const tenant = await makeUser(prisma, UserRole.TENANT);
    await properties.update(property.id, landlord.id, { isHidden: true });

    expect((await properties.findMany({})).items).toEqual([]);
    expect((await properties.findMany({ landlordId: landlord.id })).items).toEqual([]);
    const own = await properties.findMany({ landlordId: landlord.id }, landlord.id);
    expect(own.items.map((p) => [p.id, p.hiddenByLandlord])).toEqual([[property.id, true]]);

    const bookings = new BookingsService(prisma as never, {} as never, {} as never, settings, { postBookingSystemMessage: async () => null } as never);
    await expect(bookings.create(tenant.id, { propertyId: property.id } as never)).rejects.toBeInstanceOf(ForbiddenException);

    await properties.update(property.id, landlord.id, { isHidden: false });
    expect((await properties.findMany({})).items.map((p) => p.id)).toEqual([property.id]);
  });

  it("won't hide an occupied listing", async () => {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const property = await makeProperty(prisma, landlord.id, { isOccupied: true });
    await expect(properties.update(property.id, landlord.id, { isHidden: true })).rejects.toThrow(/only be hidden while nobody/);
  });
});
