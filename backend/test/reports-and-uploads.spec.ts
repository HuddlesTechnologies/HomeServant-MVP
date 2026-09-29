import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { ReportsService } from '../src/reports/reports.service';
import { extensionFitsFolder } from '../src/storage/dto/create-signed-upload-url.dto';
import { fakeGateway, fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

describe('upload folders', () => {
  it('only takes videos in property-videos, and only images everywhere else', () => {
    expect(extensionFitsFolder('tour.mp4', 'property-videos')).toBe(true);
    expect(extensionFitsFolder('tour.MOV', 'property-videos')).toBe(true);
    expect(extensionFitsFolder('cover.jpg', 'property-videos')).toBe(false);
    expect(extensionFitsFolder('cover.jpg', 'properties')).toBe(true);
    expect(extensionFitsFolder('tour.mp4', 'properties')).toBe(false);
    expect(extensionFitsFolder('avatar.webm', 'profile-photos')).toBe(false);
  });
});

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('reporting a listing (real Postgres)', () => {
  let prisma: PrismaClient;
  let reports: ReportsService;
  let notes: { userId: string; title: string }[];

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    notes = [];
    const notifier = { create: async (userId: string, _t: unknown, title: string) => void notes.push({ userId, title }) };
    reports = new ReportsService(prisma as never, notifier as never, fakeMail() as never, fakeGateway() as never);
  });

  it("lets anyone who booked, messaged about or saved a listing report it — once — and tells them when it's reviewed", async () => {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const property = await makeProperty(prisma, landlord.id);
    const stranger = await makeUser(prisma, UserRole.TENANT);
    const payer = await makeUser(prisma, UserRole.TENANT);
    const saver = await makeUser(prisma, UserRole.TENANT);
    await prisma.booking.create({ data: { tenantId: payer.id, propertyId: property.id, status: 'PAID_AWAITING_INSPECTION' } });
    await prisma.favorite.create({ data: { userId: saver.id, propertyId: property.id } });

    const reason = 'Asked me to pay outside HomeServant';
    await expect(reports.create(stranger.id, { targetType: 'PROPERTY', propertyId: property.id, reason })).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    const filed = await reports.create(payer.id, { targetType: 'PROPERTY', propertyId: property.id, reason });
    await reports.create(saver.id, { targetType: 'PROPERTY', propertyId: property.id, reason });
    await expect(reports.create(payer.id, { targetType: 'PROPERTY', propertyId: property.id, reason })).rejects.toBeInstanceOf(
      BadRequestException,
    );

    expect((await reports.findMine(payer.id)).map((r) => r.id)).toEqual([filed.id]);
    await reports.setStatus(filed.id, 'RESOLVED');
    await reports.setStatus(filed.id, 'RESOLVED');
    expect(notes).toEqual([{ userId: payer.id, title: 'Your report was reviewed' }]);
  });
});
