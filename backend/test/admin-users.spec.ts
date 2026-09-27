import { NotFoundException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { AdminService } from '../src/admin/admin.service';
import { fakePresence, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('admin Users screen (real Postgres)', () => {
  let prisma: PrismaClient;
  let admin: AdminService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    const log = { log: async () => undefined };
    admin = new AdminService(prisma as never, {} as never, {} as never, {} as never, {} as never, log as never, fakePresence(new Set()) as never, {} as never, {} as never);
  });

  it('never lists, shows, counts or edits admin accounts', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const staff = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
    await prisma.user.update({ where: { id: staff.id }, data: { deactivatedAt: new Date() } });

    const all = await admin.findUsers({});
    expect(all.items.map((u) => u.id).sort()).toEqual([tenant.id, landlord.id].sort());
    expect(all.total).toBe(2);
    expect((await admin.findUsers({ search: staff.email })).items).toEqual([]);
    expect((await admin.findUsers({ deactivatedOnly: true })).items).toEqual([]);
    expect((await admin.findUsers({ role: UserRole.ADMIN })).items).toEqual([]);
    expect((await admin.findUsers({ role: UserRole.LANDLORD })).items.map((u) => u.id)).toEqual([landlord.id]);

    const stats = await admin.stats();
    expect(stats.totalUsers).toBe(2);
    expect(stats.deactivatedAccounts).toBe(0);

    await expect(admin.findUserDetail(staff.id)).rejects.toBeInstanceOf(NotFoundException);
    expect((await admin.findUserDetail(tenant.id)).id).toBe(tenant.id);
    await expect(admin.updateUser(staff.id, { name: 'Changed' }, tenant.id)).rejects.toThrow();
    expect((await prisma.user.findUniqueOrThrow({ where: { id: staff.id } })).fullName).not.toBe('Changed');
  });
});
