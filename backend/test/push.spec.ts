import { PrismaClient, UserRole } from '@prisma/client';
import * as webpush from 'web-push';
import { PushService } from '../src/push/push.service';
import { makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

jest.mock('web-push', () => ({ setVapidDetails: jest.fn(), sendNotification: jest.fn() }));

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('PushService (real Postgres)', () => {
  let prisma: PrismaClient;
  const config = (keys: boolean) => ({
    get: (key: string, fallback?: string) =>
      keys && key === 'VAPID_PUBLIC_KEY' ? 'pub' : keys && key === 'VAPID_PRIVATE_KEY' ? 'priv' : fallback,
  });

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    jest.clearAllMocks();
  });

  it('is off without VAPID keys', async () => {
    const push = new PushService(prisma as never, config(false) as never);
    expect(push.enabled).toBe(false);
    await push.sendToUser('anyone', { title: 't', body: 'b', tag: 'x' });
    expect(webpush.sendNotification).not.toHaveBeenCalled();
  });

  it('sends to every browser a user subscribed, and forgets ones the push service says are gone', async () => {
    const user = await makeUser(prisma, UserRole.TENANT);
    const push = new PushService(prisma as never, config(true) as never);
    await push.subscribe(user.id, 'https://push.example/alive', 'k1', 'a1');
    await push.subscribe(user.id, 'https://push.example/gone', 'k2', 'a2');
    (webpush.sendNotification as jest.Mock).mockImplementation(async (sub: { endpoint: string }) => {
      if (sub.endpoint.endsWith('gone')) throw Object.assign(new Error('Gone'), { statusCode: 410 });
    });

    await push.sendToUser(user.id, { title: 'New message', body: 'Hi', tag: 't1' });

    expect(webpush.sendNotification).toHaveBeenCalledTimes(2);
    const remaining = await prisma.pushSubscription.findMany({ where: { userId: user.id } });
    expect(remaining.map((s) => s.endpoint)).toEqual(['https://push.example/alive']);
  });

  it('moves a browser\'s subscription to whoever signs in there next, and drops it on sign-out', async () => {
    const first = await makeUser(prisma, UserRole.TENANT);
    const second = await makeUser(prisma, UserRole.LANDLORD);
    const push = new PushService(prisma as never, config(true) as never);
    await push.subscribe(first.id, 'https://push.example/browser', 'k', 'a');
    await push.subscribe(second.id, 'https://push.example/browser', 'k', 'a');
    expect(await prisma.pushSubscription.count({ where: { userId: first.id } })).toBe(0);
    await push.unsubscribe(second.id, 'https://push.example/browser');
    expect(await prisma.pushSubscription.count()).toBe(0);
  });
});
