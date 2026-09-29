import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient, UserRole } from '@prisma/client';

/// These tests run against a real Postgres, never a production database:
/// set TEST_DATABASE_URL to a disposable database with the migrations
/// applied (`DATABASE_URL=$TEST_DATABASE_URL npx prisma migrate deploy`).
/// Every table is emptied before each test.
export const testDbUrl = process.env.TEST_DATABASE_URL;

export function testPrisma(): PrismaClient {
  if (!testDbUrl) throw new Error('Set TEST_DATABASE_URL to a disposable, migrated Postgres database');
  return new PrismaClient({ adapter: new PrismaPg({ connectionString: testDbUrl }) });
}

export async function resetDb(prisma: PrismaClient): Promise<void> {
  const tables = await prisma.$queryRaw<{ tablename: string }[]>`
    SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename <> '_prisma_migrations'`;
  if (tables.length === 0) return;
  await prisma.$executeRawUnsafe(`TRUNCATE ${tables.map((t) => `"${t.tablename}"`).join(', ')} CASCADE`);
}

let counter = 0;
export function makeUser(
  prisma: PrismaClient,
  role: UserRole,
  extra: Partial<{ fullName: string; adminLevel: 'SUPPORT' | 'MODERATOR' | 'SUPER_ADMIN'; adminOnDuty: boolean }> = {},
) {
  counter++;
  return prisma.user.create({
    data: { email: `user${counter}-${Date.now()}@test.local`, role, fullName: extra.fullName ?? `${role} ${counter}`, ...extra },
  });
}

export function makeProperty(prisma: PrismaClient, landlordId: string, extra: Partial<{ isOccupied: boolean; category: 'HOUSE' | 'SHORTLET' }> = {}) {
  return prisma.property.create({
    data: {
      landlordId,
      title: 'Test House',
      location: 'Lekki',
      state: 'Lagos',
      category: extra.category ?? 'HOUSE',
      price: 1_000_000,
      priceUnit: extra.category === 'SHORTLET' ? 'NIGHT' : 'YEAR',
      bedrooms: 2,
      bathrooms: 2,
      description: 'A test property for automated tests',
      isOccupied: extra.isOccupied ?? false,
    },
  });
}

/// Records every socket event instead of sending it.
export function fakeGateway() {
  return {
    events: [] as { kind: string; args: unknown[] }[],
    broadcastMessage(...args: unknown[]) {
      this.events.push({ kind: 'broadcastMessage', args });
    },
    broadcastToAdmins(...args: unknown[]) {
      this.events.push({ kind: 'broadcastToAdmins', args });
    },
    emitToUser(...args: unknown[]) {
      this.events.push({ kind: 'emitToUser', args });
    },
    async evictUnauthorizedFromThread() {},
  };
}

export function fakePresence(online: Set<string>) {
  return { isOnline: (id: string) => online.has(id), markOnline() {}, markOffline: async () => {} };
}

export function fakeMail() {
  return { sent: [] as { to: string; subject: string; text: string }[], async send(to: string, subject: string, _html: string, text: string) {
    this.sent.push({ to, subject, text });
  } };
}
