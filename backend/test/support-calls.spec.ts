import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { ChatService } from '../src/chat/chat.service';
import { SupportToolsService } from '../src/chat/support-tools.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { fakeGateway, fakeMail, fakePresence, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('calling a customer from a chat (real Postgres)', () => {
  let prisma: PrismaClient;
  let chat: ChatService;
  let tools: SupportToolsService;
  let logged: { type: string; opts: { actorId?: string; targetId?: string; reason?: string } }[];

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    process.env.SUPPORT_AUTO_ASSIGN = 'false';
    logged = [];
    const gateway = fakeGateway();
    const activityLog = { log: async (type: string, opts: never) => void logged.push({ type, opts }) };
    const notifications = new NotificationsService(prisma as never, gateway as never, { sendToUser: async () => undefined } as never);
    chat = new ChatService(
      prisma as never,
      notifications,
      fakeMail() as never,
      fakePresence(new Set()) as never,
      gateway as never,
      activityLog as never,
      { assertIsOwnImage: async () => undefined } as never,
    );
    tools = new SupportToolsService(prisma as never, chat, gateway as never, fakePresence(new Set()) as never, activityLog as never);
  });
  afterEach(() => {
    delete process.env.SUPPORT_AUTO_ASSIGN;
  });

  async function claimedSupportChat() {
    const customer = await makeUser(prisma, UserRole.TENANT, { fullName: 'Tolu Customer' });
    await prisma.user.update({ where: { id: customer.id }, data: { phoneNumber: '+2348012345678' } });
    const handler = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
    const thread = await chat.openSupportThread(customer.id, 'PAYMENTS');
    await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Please call me' });
    await chat.claimThread(thread.id, handler.id);
    return { customer, handler, thread };
  }

  it('logs the call with its reason against the chat and in the activity log, and returns the number', async () => {
    const { customer, handler, thread } = await claimedSupportChat();
    const result = await tools.logCall(thread.id, handler.id, '  Confirming the refund account details  ');
    expect(result.phoneNumber).toBe('+2348012345678');

    const calls = await tools.listCalls(thread.id, handler.id);
    expect(calls).toHaveLength(1);
    expect(calls[0]).toMatchObject({
      threadId: thread.id,
      adminId: handler.id,
      customerId: customer.id,
      reason: 'Confirming the refund account details',
    });
    expect(logged.filter((l) => l.type === 'SUPPORT_CUSTOMER_CALLED')).toEqual([
      {
        type: 'SUPPORT_CUSTOMER_CALLED',
        opts: { actorId: handler.id, targetId: customer.id, reason: 'Confirming the refund account details' },
      },
    ]);
  });

  it("lets super admins see and place calls, but not an admin who isn't handling the chat", async () => {
    const { thread } = await claimedSupportChat();
    const other = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
    const superAdmin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    await expect(tools.logCall(thread.id, other.id, 'Just checking in with them')).rejects.toBeInstanceOf(ForbiddenException);
    await expect(tools.listCalls(thread.id, other.id)).rejects.toBeInstanceOf(ForbiddenException);
    await tools.logCall(thread.id, superAdmin.id, 'Escalated payment problem');
    expect(await tools.listCalls(thread.id, superAdmin.id)).toHaveLength(1);
  });

  it("refuses when the customer has no phone number, without logging anything", async () => {
    const { customer, handler, thread } = await claimedSupportChat();
    await prisma.user.update({ where: { id: customer.id }, data: { phoneNumber: null } });
    await expect(tools.logCall(thread.id, handler.id, 'Confirming the refund')).rejects.toBeInstanceOf(BadRequestException);
    expect(await prisma.supportCallLog.count()).toBe(0);
    expect(logged.filter((l) => l.type === 'SUPPORT_CUSTOMER_CALLED')).toEqual([]);
  });
});
