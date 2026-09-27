import { BadRequestException, ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { EvictionsService } from '../src/evictions/evictions.service';
import { fakeMail, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('eviction requests (real Postgres)', () => {
  let prisma: PrismaClient;
  let mail: ReturnType<typeof fakeMail>;
  let notes: { userId: string; title: string }[];
  let evictions: EvictionsService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    mail = fakeMail();
    notes = [];
    const notifications = { create: async (userId: string, _type: unknown, title: string) => void notes.push({ userId, title }) };
    evictions = new EvictionsService(prisma as never, notifications as never, mail as never);
  });

  async function tenancy(status: 'MOVED_IN' | 'PAID' = 'MOVED_IN') {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    const property = await makeProperty(prisma, landlord.id, { isOccupied: true });
    const booking = await prisma.booking.create({
      data: {
        propertyId: property.id,
        tenantId: tenant.id,
        status,
        leaseStartDate: new Date(Date.now() - 30 * 86_400_000),
        leaseEndDate: new Date(Date.now() + 300 * 86_400_000),
      },
    });
    return { tenant, landlord, admin, property, booking };
  }

  const reason = 'Tenant has repeatedly damaged the property and ignored notices.';

  it('only the landlord of a current tenancy can file, once at a time, and the tenant is told', async () => {
    const { tenant, landlord, booking } = await tenancy();
    const stranger = await makeUser(prisma, UserRole.LANDLORD);
    await expect(evictions.create(stranger.id, booking.id, reason)).rejects.toBeInstanceOf(NotFoundException);

    const request = await evictions.create(landlord.id, booking.id, reason);
    expect(request.status).toBe('PENDING');
    expect(notes.some((n) => n.userId === tenant.id)).toBe(true);
    expect(notes.some((n) => n.title === 'Eviction request to review')).toBe(true);
    expect(mail.sent.some((m) => m.to === tenant.email)).toBe(true);
    await expect(evictions.create(landlord.id, booking.id, reason)).rejects.toBeInstanceOf(ConflictException);
  });

  it('rejects a tenancy the tenant has not moved into', async () => {
    const { landlord, booking } = await tenancy('PAID');
    await expect(evictions.create(landlord.id, booking.id, reason)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('filing changes nothing; approval ends the lease and relists the property', async () => {
    const { landlord, tenant, admin, property, booking } = await tenancy();
    const request = await evictions.create(landlord.id, booking.id, reason);
    expect((await prisma.property.findUniqueOrThrow({ where: { id: property.id } })).isOccupied).toBe(true);

    await evictions.respond(tenant.id, request.id, 'This is not true, I have receipts.');
    await expect(evictions.respond(landlord.id, request.id, 'nope nope')).rejects.toBeInstanceOf(ForbiddenException);

    const decided = await evictions.review(admin.id, request.id, 'APPROVE');
    expect(decided.status).toBe('APPROVED');
    expect(decided.reviewedById).toBe(admin.id);
    expect(decided.tenantResponse).toBe('This is not true, I have receipts.');
    expect((await prisma.property.findUniqueOrThrow({ where: { id: property.id } })).isOccupied).toBe(false);
    const ended = await prisma.booking.findUniqueOrThrow({ where: { id: booking.id } });
    expect(ended.leaseEndDate!.getTime()).toBeLessThanOrEqual(Date.now());
    await expect(evictions.review(admin.id, request.id, 'REJECT', 'changed my mind here')).rejects.toBeInstanceOf(ConflictException);
  });

  it('rejection needs a note and leaves the tenancy alone; landlords can withdraw', async () => {
    const { landlord, admin, property, booking } = await tenancy();
    const first = await evictions.create(landlord.id, booking.id, reason);
    await expect(evictions.review(admin.id, first.id, 'REJECT')).rejects.toBeInstanceOf(BadRequestException);
    const rejected = await evictions.review(admin.id, first.id, 'REJECT', 'Not enough evidence was provided.');
    expect(rejected.status).toBe('REJECTED');
    expect((await prisma.property.findUniqueOrThrow({ where: { id: property.id } })).isOccupied).toBe(true);

    const second = await evictions.create(landlord.id, booking.id, reason);
    expect((await evictions.cancel(landlord.id, second.id)).status).toBe('CANCELLED');
    await expect(evictions.review(admin.id, second.id, 'APPROVE')).rejects.toBeInstanceOf(ConflictException);
  });
});
