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

  it('the tenant page refuses a landlord, and the landlord page refuses a tenant', async () => {
    await account(UserRole.TENANT, 'tenant@test.local');
    await account(UserRole.LANDLORD, 'landlord@test.local');
    await expect(auth.login({ email: 'landlord@test.local', password: 'secret-pass', portal: 'TENANT' })).rejects.toThrow(
      /landlord account.*landlord page/,
    );
    await expect(auth.login({ email: 'tenant@test.local', password: 'secret-pass', portal: 'LANDLORD' })).rejects.toThrow(
      /tenant account.*tenant page/,
    );
    await expect(auth.login({ email: 'tenant@test.local', password: 'secret-pass', portal: 'TENANT' })).resolves.toHaveProperty('accessToken');
    await expect(auth.login({ email: 'landlord@test.local', password: 'secret-pass', portal: 'LANDLORD' })).resolves.toHaveProperty(
      'accessToken',
    );
    // A wrong password still reveals nothing about the account's role.
    await expect(auth.login({ email: 'landlord@test.local', password: 'wrong', portal: 'TENANT' })).rejects.toThrow(
      /Incorrect email or password/,
    );
    // Older app builds ('APP') still let either in.
    await expect(auth.login({ email: 'landlord@test.local', password: 'secret-pass', portal: 'APP' })).resolves.toHaveProperty(
      'accessToken',
    );
  });

  it('Google on the wrong page is refused and the account is not linked', async () => {
    const landlord = await account(UserRole.LANDLORD, 'landlord@test.local');
    const googleClient = (auth as unknown as { googleClient: { verifyIdToken: unknown } }).googleClient;
    googleClient.verifyIdToken = async () => ({
      getPayload: () => ({ sub: 'google-456', email: 'landlord@test.local', email_verified: true }),
    });
    await expect(auth.googleAuth({ idToken: 'x', portal: 'TENANT' } as never)).rejects.toThrow(/landlord page/);
    expect((await prisma.user.findUniqueOrThrow({ where: { id: landlord.id } })).googleId).toBeNull();
    await expect(auth.googleAuth({ idToken: 'x', portal: 'LANDLORD' } as never)).resolves.toHaveProperty('accessToken');
  });

  /// Makes Google's token check return [payload], and records the audience
  /// it was asked to check against.
  function googleReturns(payload: Record<string, unknown>) {
    const audiences: unknown[] = [];
    const googleClient = (auth as unknown as { googleClient: { verifyIdToken: unknown } }).googleClient;
    googleClient.verifyIdToken = async (opts: { audience: unknown }) => {
      audiences.push(opts.audience);
      return { getPayload: () => payload };
    };
    return audiences;
  }

  it("Google sign-up creates the account with the page's role, verified, checked against our client ID", async () => {
    const audiences = googleReturns({ sub: 'google-new', email: 'New.Person@Test.local', email_verified: true, name: 'New Person' });
    const result = await auth.googleAuth({ idToken: 'x', role: UserRole.LANDLORD, portal: 'LANDLORD' } as never);
    expect(result).toHaveProperty('accessToken');
    expect(audiences).toEqual(['google-client']);
    const user = await prisma.user.findUniqueOrThrow({ where: { email: 'new.person@test.local' } });
    expect(user).toMatchObject({ role: UserRole.LANDLORD, googleId: 'google-new', fullName: 'New Person' });
    expect(user.emailVerifiedAt).not.toBeNull();
    // Signing in again finds the same account rather than making another.
    await expect(auth.googleAuth({ idToken: 'x', role: UserRole.LANDLORD, portal: 'LANDLORD' } as never)).resolves.toHaveProperty('accessToken');
    expect(await prisma.user.count()).toBe(1);
  });

  it('Google on an existing email/password account links it and signs in', async () => {
    const tenant = await account(UserRole.TENANT, 'tenant@test.local');
    googleReturns({ sub: 'google-789', email: 'tenant@test.local', email_verified: true });
    await expect(auth.googleAuth({ idToken: 'x', role: UserRole.TENANT, portal: 'TENANT' } as never)).resolves.toHaveProperty('accessToken');
    expect((await prisma.user.findUniqueOrThrow({ where: { id: tenant.id } })).googleId).toBe('google-789');
  });

  it('a bad Google token, or one with an unverified email, is refused without creating an account', async () => {
    const googleClient = (auth as unknown as { googleClient: { verifyIdToken: unknown } }).googleClient;
    googleClient.verifyIdToken = async () => {
      throw new Error('Wrong recipient, payload audience != requiredAudience');
    };
    await expect(auth.googleAuth({ idToken: 'x', role: UserRole.TENANT } as never)).rejects.toThrow(/Invalid Google sign-in token/);
    googleReturns({ sub: 'google-unverified', email: 'u@test.local', email_verified: false });
    await expect(auth.googleAuth({ idToken: 'x', role: UserRole.TENANT } as never)).rejects.toThrow(/isn't verified/);
    expect(await prisma.user.count()).toBe(0);
  });
});
