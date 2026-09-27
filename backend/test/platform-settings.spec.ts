import { ForbiddenException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { BookingsService } from '../src/bookings/bookings.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { PropertiesService } from '../src/properties/properties.service';
import { makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('platform controls: only verified landlords (real Postgres)', () => {
  let prisma: PrismaClient;
  let settings: PlatformSettingsService;
  let properties: PropertiesService;
  let bookings: BookingsService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    settings = new PlatformSettingsService(prisma as never);
    const reviews = { summaryForProperties: async () => new Map() };
    properties = new PropertiesService(prisma as never, reviews as never, {} as never, settings);
    const notifications = { create: async () => undefined };
    const payments = { chargeBooking: async () => ({ reference: 'r', authorizationUrl: 'https://pay' }) };
    bookings = new BookingsService(prisma as never, notifications as never, payments as never, settings);
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
});
