import { PrismaClient, UserRole } from '@prisma/client';
import { AdminService } from '../src/admin/admin.service';
import { ChatService } from '../src/chat/chat.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { fakeGateway, fakeMail, fakePresence, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('support chat: admin names, topics and auto-assignment (real Postgres)', () => {
  let prisma: PrismaClient;
  let online: Set<string>;
  let gateway: ReturnType<typeof fakeGateway>;
  let mail: ReturnType<typeof fakeMail>;
  let chat: ChatService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    delete process.env.SUPPORT_AUTO_ASSIGN;
    online = new Set();
    gateway = fakeGateway();
    mail = fakeMail();
    const push = { sendToUser: async () => undefined };
    const notifications = new NotificationsService(prisma as never, gateway as never, push as never);
    chat = new ChatService(
      prisma as never,
      notifications,
      mail as never,
      fakePresence(online) as never,
      gateway as never,
      { log: async () => undefined } as never,
      { assertIsOwnImage: async () => undefined } as never,
    );
  });

  it("shows customers only the admin's first name, and admins the full name", async () => {
    const customer = await makeUser(prisma, UserRole.TENANT, { fullName: 'Tolu Customer' });
    const admin = await makeUser(prisma, UserRole.ADMIN, { fullName: 'Ada Lovelace Okafor', adminLevel: 'SUPPORT' });
    await prisma.user.update({ where: { id: admin.id }, data: { firstName: 'Ada', lastName: 'Okafor' } });
    online.add(admin.id);

    const thread = await chat.openSupportThread(customer.id, 'PAYMENTS');
    await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Hello' });
    const reply = await chat.sendMessage(thread.id, admin.id, UserRole.ADMIN, { body: 'Hi, how can I help?' });
    expect(reply.sender?.fullName).toBe('Ada');

    const [inbox] = await chat.findForUser(customer.id, false);
    expect(inbox.otherParticipants.map((p) => p.fullName)).toEqual(['Ada']);
    const summary = await chat.getThreadSummary(thread.id, customer.id, UserRole.TENANT);
    expect(summary.assignedAdmin?.fullName).toBe('Ada');
    expect(summary.otherParticipants.map((p) => p.fullName)).toEqual(['Ada']);
    const messages = await chat.findMessages(thread.id, customer.id, UserRole.TENANT);
    expect(messages.find((m) => m.senderId === admin.id)?.sender?.fullName).toBe('Ada');
    const note = await prisma.notification.findFirstOrThrow({ where: { userId: customer.id, type: 'NEW_MESSAGE' } });
    expect(note.title).toBe('New message from Ada');

    // The admin still sees the customer's (and their own colleagues') full names.
    const [adminInbox] = await chat.findForUser(admin.id, true);
    expect(adminInbox.otherParticipants.map((p) => p.fullName)).toEqual(['Tolu Customer']);
  });

  it('falls back to the first word of the full name for admins without a first name', async () => {
    const customer = await makeUser(prisma, UserRole.TENANT);
    const admin = await makeUser(prisma, UserRole.ADMIN, { fullName: 'Bola Adeyemi', adminLevel: 'SUPPORT' });
    const thread = await chat.openSupportThread(customer.id);
    await chat.sendMessage(thread.id, admin.id, UserRole.ADMIN, { body: 'Hello' });
    const summary = await chat.getThreadSummary(thread.id, customer.id, UserRole.TENANT);
    expect(summary.assignedAdmin?.fullName).toBe('Bola');
  });

  it('keeps the topic the customer picks, including a new pick on an open conversation', async () => {
    const customer = await makeUser(prisma, UserRole.TENANT);
    const first = await chat.openSupportThread(customer.id, 'BOOKING');
    expect(first.supportTopic).toBe('BOOKING');
    const again = await chat.openSupportThread(customer.id, 'PAYMENTS');
    expect(again.id).toBe(first.id);
    expect(again.supportTopic).toBe('PAYMENTS');
    const [queued] = await chat.findSupportQueue();
    expect(queued.supportTopic).toBe('PAYMENTS');
    expect((await prisma.supportChatStat.findFirstOrThrow({ where: { threadId: first.id } })).topic).toBe('PAYMENTS');
  });

  it('records an automatic assignment as AUTO_ASSIGN and says so in the notification', async () => {
    const customer = await makeUser(prisma, UserRole.TENANT);
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
    const thread = await chat.openSupportThread(customer.id, 'ACCOUNT');
    await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'I cannot sign in' });
    // Nobody was online when it arrived; the queue sweep hands it over.
    online.add(admin.id);
    expect(await chat.assignWaitingQueue()).toBe(1);

    const history = await chat.getHandlingHistory(thread.id, admin.id);
    expect(history.entries.map((e) => e.kind)).toEqual(['AUTO_ASSIGN']);
    expect(history.entries[0].from).toBeNull();
    const note = await prisma.notification.findFirstOrThrow({
      where: { userId: admin.id, title: 'Auto assigned to you by system admin' },
    });
    expect(note.body).toContain('about Account');
  });

  it('creates invited admins with separate first and last names', async () => {
    const superAdmin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
    const otp = { generate: async () => '1234', verify: async () => undefined };
    const admins = new AdminService(
      prisma as never,
      {} as never,
      mail as never,
      {} as never,
      otp as never,
      { log: async () => undefined } as never,
      fakePresence(new Set()) as never,
      {} as never,
      gateway as never,
    );
    await admins.requestAdminOtp(
      { email: 'new.admin@test.local', firstName: ' Chidi ', lastName: 'Eze', level: 'SUPPORT' },
      superAdmin.id,
    );
    const created = await admins.confirmAdminOtp({ email: 'new.admin@test.local', code: '1234' });
    expect(created).toMatchObject({ firstName: 'Chidi', lastName: 'Eze', fullName: 'Chidi Eze' });

    // Older console builds still send one full name.
    await admins.requestAdminOtp({ email: 'old.form@test.local', fullName: 'Ngozi Ama Obi', level: 'SUPPORT' });
    const legacy = await admins.confirmAdminOtp({ email: 'old.form@test.local', code: '1234' });
    expect(legacy).toMatchObject({ firstName: 'Ngozi', lastName: 'Ama Obi', fullName: 'Ngozi Ama Obi' });
  });
});
