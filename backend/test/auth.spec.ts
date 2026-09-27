import { ForbiddenException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaClient, UserRole } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { AuthService } from '../src/auth/auth.service';
import { resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('sign-in pages and account types (real Postgres)', () => {
  let prisma: PrismaClient;
  let auth: AuthService;
  let adminLogins: number;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    adminLogins = 0;
    const secrets: Record<string, string> = {
      JWT_ACCESS_SECRET: 'a',
      JWT_REFRESH_SECRET: 'r',
      GOOGLE_CLIENT_ID: 'google-client',
    };
    const config = { get: (k: string, d?: string) => secrets[k] ?? d, getOrThrow: (k: string) => secrets[k] };
    const otp = { issue: async () => undefined, verify: async () => undefined };
    const activityLog = { log: async () => void adminLogins++ };
    auth = new AuthService(prisma as never, new JwtService({}), config as never, otp as never, {} as never, activityLog as never, { removePrivateFilesFor: async () => undefined } as never);
  });

  async function account(role: UserRole, email: string) {
    return prisma.user.create({
      data: {
        email,
        role,
        passwordHash: await bcrypt.hash('secret-pass', 4),
        emailVerifiedAt: new Date(),
        ...(role === UserRole.ADMIN ? { adminLevel: 'SUPPORT' as const } : {}),
      },
    });
  }

  it('refuses an admin on the tenant/landlord sign-in page', async () => {
    await account(UserRole.ADMIN, 'admin@test.local');
    await expect(auth.login({ email: 'admin@test.local', password: 'secret-pass', portal: 'APP' })).rejects.toThrow(
      /admin console/,
    );
    expect(adminLogins).toBe(0);
  });

  it('refuses a tenant on the admin sign-in page, and lets an admin in there', async () => {
    await account(UserRole.TENANT, 'tenant@test.local');
    await account(UserRole.ADMIN, 'admin@test.local');
    await expect(auth.login({ email: 'tenant@test.local', password: 'secret-pass', portal: 'ADMIN' })).rejects.toThrow(
      ForbiddenException,
    );
    const ok = await auth.login({ email: 'admin@test.local', password: 'secret-pass', portal: 'ADMIN' });
    expect('accessToken' in ok && ok.accessToken).toBeTruthy();
    expect(adminLogins).toBe(1);
  });

  it('still says only "incorrect email or password" for a wrong password, whatever the page', async () => {
    await account(UserRole.ADMIN, 'admin@test.local');
    await expect(auth.login({ email: 'admin@test.local', password: 'wrong', portal: 'APP' })).rejects.toThrow(
      /Incorrect email or password/,
    );
  });

  it('never lets an admin sign in with Google, and does not link their account', async () => {
    const admin = await account(UserRole.ADMIN, 'admin@test.local');
    const googleClient = (auth as unknown as { googleClient: { verifyIdToken: unknown } }).googleClient;
    googleClient.verifyIdToken = async () => ({
      getPayload: () => ({ sub: 'google-123', email: 'admin@test.local', email_verified: true }),
    });
    await expect(auth.googleAuth({ idToken: 'x' } as never)).rejects.toThrow(/admin console/);
    expect((await prisma.user.findUniqueOrThrow({ where: { id: admin.id } })).googleId).toBeNull();
  });
});
