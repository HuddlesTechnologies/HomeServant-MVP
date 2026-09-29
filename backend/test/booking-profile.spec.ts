import { PrismaClient, UserRole } from '@prisma/client';
import { BookingsService } from '../src/bookings/bookings.service';
import { UsersService } from '../src/users/users.service';
import { makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb("tenant booking profile (real Postgres)", () => {
  let prisma: PrismaClient;
  let users: UsersService;
  let bookings: BookingsService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    users = new UsersService(prisma as never, {} as never, { create: async () => undefined } as never, {} as never, {} as never);
    bookings = new BookingsService(prisma as never, {} as never, {} as never, { requireVerifiedLandlords: async () => false } as never);
  });

  it('saves a background and tidied hobbies, and shows them to the landlord with the booking request', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const property = await makeProperty(prisma, landlord.id, { category: 'SHORTLET' });

    const saved = await users.updateProfile(tenant.id, {
      bio: '  Nurse at LUTH, quiet, non-smoker.  ',
      hobbies: [' Cooking ', 'football', 'cooking', ''],
    });
    expect(saved.bio).toBe('Nurse at LUTH, quiet, non-smoker.');
    expect(saved.hobbies).toEqual(['Cooking', 'football']);

    await prisma.booking.create({ data: { tenantId: tenant.id, propertyId: property.id, status: 'PENDING' } });
    const [request] = await bookings.findForLandlord(landlord.id);
    expect(request.tenant).toMatchObject({ bio: 'Nurse at LUTH, quiet, non-smoker.', hobbies: ['Cooking', 'football'] });

    // An empty string clears the background.
    expect((await users.updateProfile(tenant.id, { bio: '' })).bio).toBeNull();
  });
});
