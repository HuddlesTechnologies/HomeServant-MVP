import { ForbiddenException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { PrismaClient, UserRole } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { AdminService } from '../src/admin/admin.service';
import { AuthService } from '../src/auth/auth.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { PlatformSettingsService } from '../src/platform-settings/platform-settings.service';
import { PropertiesService } from '../src/properties/properties.service';
import { fakeGateway, fakeMail, fakePresence, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('permanent bans (real Postgres)', () => {
  let prisma: PrismaClient;
  let auth: AuthService;
  let admin: AdminService;
  let properties: PropertiesService;
  let mail: ReturnType<typeof fakeMail>;
  let gateway: ReturnType<typeof fakeGateway>;
  let logged: string[];

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    mail = fakeMail();
    gateway = fakeGateway();
    logged = [];
    const secrets: Record<string, string> = { JWT_ACCESS_SECRET: 'a', JWT_REFRESH_SECRET: 'r', GOOGLE_CLIENT_ID: 'g' };
    const config = { get: (k: string, d?: string) => secrets[k] ?? d, getOrThrow: (k: string) => secrets[k] };
    const otp = { issue: async () => undefined, verify: async () => undefined };
    const activityLog = { log: async (type: string) => void logged.push(type) };
    auth = new AuthService(prisma as never, new JwtService({}), config as never, otp as never, mail as never, activityLog as never, { removePrivateFilesFor: async () => undefined } as never);
    const notifications = new NotificationsService(prisma as never, gateway as never, { sendToUser: async () => undefined } as never);
    admin = new AdminService(prisma as never, auth, mail as never, notifications, otp as never, activityLog as never, fakePresence(new Set()) as never, {} as never, gateway as never);
    const settings = new PlatformSettingsService(prisma as never, notifications, mail as never);
    properties = new PropertiesService(prisma as never, { summaryForProperties: async () => new Map() } as never, {} as never, settings, notifications);
  });

  async function landlordWithListing() {
    const landlord = await prisma.user.create({
      data: { email: `l${Date.now()}@test.local`, role: UserRole.LANDLORD, passwordHash: await bcrypt.hash('secret-pass', 4), emailVerifiedAt: new Date() },
    });
    const property = await makeProperty(prisma, landlord.id);
    return { landlord, property };
  }

  it('signs them out, blocks sign-in with the reason, hides their listings and tells them', async () => {
    const moderator = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
    const { landlord, property } = await landlordWithListing();
    const session = await auth.login({ email: landlord.email, password: 'secret-pass' } as never);
    expect('refreshToken' in session).toBe(true);

    await admin.banUser(landlord.id, 'Posted fake listings with stolen photos', moderator.id);

    await expect(auth.login({ email: landlord.email, password: 'secret-pass' } as never)).rejects.toThrow(
      /permanently banned.*Posted fake listings with stolen photos/,
    );
    // An open app learns it was a ban (and why) when it next refreshes.
    await expect(auth.refresh((session as { refreshToken: string }).refreshToken)).rejects.toThrow(ForbiddenException);
    await expect(auth.refresh((session as { refreshToken: string }).refreshToken)).rejects.toThrow(/stolen photos/);
    expect((await properties.findMany({})).items.map((p) => p.id)).not.toContain(property.id);

    expect(logged).toContain('ADMIN_USER_BANNED');
    expect(mail.sent.find((m) => m.to === landlord.email)?.subject).toBe('Your HomeServant account has been permanently banned');
    const note = await prisma.notification.findFirstOrThrow({ where: { userId: landlord.id, type: 'ACCOUNT_BANNED' } });
    expect(note.body).toContain('Posted fake listings');
    expect(gateway.events).toContainEqual({ kind: 'emitToUser', args: [landlord.id, 'account:banned', { reason: 'Posted fake listings with stolen photos' }] });
    expect((await admin.findUsers({ bannedOnly: true })).items.map((u) => u.id)).toEqual([landlord.id]);
  });

  it('only lets a super admin lift a ban, which restores sign-in and listings', async () => {
    const moderator = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
    const { landlord, property } = await landlordWithListing();
    const superAdmin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    await admin.banUser(landlord.id, 'Posted fake listings with stolen photos', moderator.id);
    await expect(admin.unbanUser(landlord.id, 'Owner proved the photos are theirs', moderator.id)).rejects.toBeInstanceOf(
      ForbiddenException,
    );
    await admin.unbanUser(landlord.id, 'Owner proved the photos are theirs', superAdmin.id);

    const session = await auth.login({ email: landlord.email, password: 'secret-pass' } as never);
    expect('accessToken' in session).toBe(true);
    expect((await properties.findMany({})).items.map((p) => p.id)).toContain(property.id);
    expect(logged).toContain('ADMIN_USER_UNBANNED');
  });

  it("can't ban an admin", async () => {
    const moderator = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
    const other = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
    await expect(admin.banUser(other.id, 'Should never work at all', moderator.id)).rejects.toBeInstanceOf(ForbiddenException);
  });
});
