import { PrismaClient, UserRole } from '@prisma/client';
import { UsersService } from '../src/users/users.service';
import { makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('signup profile completion (real Postgres)', () => {
  let prisma: PrismaClient;
  let users: UsersService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    const storage = { assertIsOwnImage: async () => undefined };
    users = new UsersService(prisma as never, {} as never, { create: async () => undefined } as never, storage as never);
  });

  it('is only marked complete once every required signup field is filled in', async () => {
    const user = await makeUser(prisma, UserRole.TENANT);
    const completedAt = async () => (await prisma.user.findUniqueOrThrow({ where: { id: user.id } })).profileCompletedAt;

    await users.updateProfile(user.id, {
      fullName: 'Ada Obi',
      phoneNumber: '08012345678',
      gender: 'FEMALE',
      occupation: 'Nurse',
      maritalStatus: 'SINGLE',
    } as never);
    expect(await completedAt()).toBeNull(); // no address, date of birth or photo yet

    await users.updateProfile(user.id, { houseAddress: '12 Allen Avenue', dateOfBirth: '1995-05-20' } as never);
    expect(await completedAt()).toBeNull(); // still no photo

    await users.updateProfile(user.id, { profilePhotoUrl: 'https://x.supabase.co/storage/v1/object/public/uploads/profile-photos/a.jpg' } as never);
    expect(await completedAt()).not.toBeNull();
  });
});
