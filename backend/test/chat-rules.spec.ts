import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { AdminService } from '../src/admin/admin.service';
import { ChatService } from '../src/chat/chat.service';
import { SupportAlertsService } from '../src/chat/support-alerts.service';
import { SupportMetricsService } from '../src/chat/support-metrics.service';
import { SupportToolsService } from '../src/chat/support-tools.service';
import { UnreadMessageEmailService } from '../src/chat/unread-message-email.service';
import { NotificationsService } from '../src/notifications/notifications.service';
import { PaymentsService } from '../src/payments/payments.service';
import { PropertiesService } from '../src/properties/properties.service';
import { fakeGateway, fakeMail, fakePresence, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('messaging, support and listing rules (real Postgres)', () => {
  let prisma: PrismaClient;
  let online: Set<string>;
  let gateway: ReturnType<typeof fakeGateway>;
  let mail: ReturnType<typeof fakeMail>;
  let pushes: { userId: string; title: string }[];
  let notifications: NotificationsService;
  let chat: ChatService;
  let tools: SupportToolsService;

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
    pushes = [];
    const push = { sendToUser: async (userId: string, p: { title: string }) => void pushes.push({ userId, title: p.title }) };
    notifications = new NotificationsService(prisma as never, gateway as never, push as never);
    const activityLog = { log: async () => undefined };
    const storage = { assertIsOwnImage: async () => undefined };
    chat = new ChatService(
      prisma as never,
      notifications,
      mail as never,
      fakePresence(online) as never,
      gateway as never,
      activityLog as never,
      storage as never,
    );
    tools = new SupportToolsService(prisma as never, chat, gateway as never, fakePresence(online) as never);
  });

  async function tenantLandlordProperty() {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const property = await makeProperty(prisma, landlord.id);
    return { tenant, landlord, property };
  }

  // --- Tenant/landlord messaging is tied to payment -------------------------

  describe('tenant/landlord payment rules', () => {
    it('stops a tenant who has not paid from messaging the landlord', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      await expect(
        chat.findOrCreateThread(tenant.id, { recipientId: landlord.id, propertyId: property.id }),
      ).rejects.toThrow(ForbiddenException);
    });

    it('lets a tenant who has paid message the landlord', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      await prisma.booking.create({ data: { propertyId: property.id, tenantId: tenant.id, status: 'PAID_AWAITING_INSPECTION' } });
      const thread = await chat.findOrCreateThread(tenant.id, { recipientId: landlord.id, propertyId: property.id });
      await expect(chat.sendMessage(thread.id, tenant.id, UserRole.TENANT, { body: 'Hello' })).resolves.toBeDefined();
    });

    it('lets the landlord reach out first, and the tenant reply', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      const thread = await chat.findOrCreateThread(landlord.id, { recipientId: tenant.id, propertyId: property.id });
      await expect(chat.sendMessage(thread.id, tenant.id, UserRole.TENANT, { body: 'Too early' })).rejects.toThrow(ForbiddenException);
      await chat.sendMessage(thread.id, landlord.id, UserRole.LANDLORD, { body: 'About your request' });
      await expect(chat.sendMessage(thread.id, tenant.id, UserRole.TENANT, { body: 'Thanks' })).resolves.toBeDefined();
    });

    it('closes the chat both ways after a refund, until the tenant pays again', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      const paid = await prisma.booking.create({ data: { propertyId: property.id, tenantId: tenant.id, status: 'PAID_AWAITING_INSPECTION' } });
      const thread = await chat.findOrCreateThread(tenant.id, { recipientId: landlord.id, propertyId: property.id });
      await chat.sendMessage(thread.id, landlord.id, UserRole.LANDLORD, { body: 'Welcome' });

      await prisma.booking.update({ where: { id: paid.id }, data: { status: 'REFUNDED' } });
      await expect(chat.sendMessage(thread.id, tenant.id, UserRole.TENANT, { body: 'Hi' })).rejects.toThrow(/refunded/);
      await expect(chat.sendMessage(thread.id, landlord.id, UserRole.LANDLORD, { body: 'Hi' })).rejects.toThrow(/refunded/);
      const summary = await chat.getThreadSummary(thread.id, landlord.id, UserRole.LANDLORD);
      expect(summary.lockedReason).toMatch(/refunded/);
      expect(summary.canReply).toBe(false);

      await prisma.booking.create({ data: { propertyId: property.id, tenantId: tenant.id, status: 'PAID_AWAITING_INSPECTION' } });
      await expect(chat.sendMessage(thread.id, tenant.id, UserRole.TENANT, { body: 'Paid again' })).resolves.toBeDefined();
    });

    it('treats a landlord rejection of a paid booking like a refund, and tells both sides in the chat', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      const booking = await prisma.booking.create({
        data: { propertyId: property.id, tenantId: tenant.id, status: 'PAID_AWAITING_INSPECTION' },
      });
      await prisma.payment.create({
        data: {
          purpose: 'RENTAL_BOOKING',
          bookingId: booking.id,
          payerId: tenant.id,
          recipientUserId: landlord.id,
          amount: 100_000_00,
          platformFeeAmount: 0,
          paystackReference: `ref-${booking.id}`,
          status: 'PAID_HELD',
        },
      });
      const paystack = { refundTransaction: jest.fn().mockResolvedValue(undefined), refundedSoFar: jest.fn().mockResolvedValue(0) };
      const payments = new PaymentsService(prisma as never, paystack as never, notifications, mail as never, chat, { payUnverifiedLandlords: async () => true } as never);
      await payments.rejectBookingByLandlord(booking.id, landlord.id);

      const thread = await prisma.thread.findFirstOrThrow({ where: { propertyId: property.id } });
      const notice = await prisma.message.findFirstOrThrow({ where: { threadId: thread.id, type: 'SYSTEM' } });
      expect(notice.body).toMatch(/rejected/);
      const rejectNotification = await prisma.notification.findFirstOrThrow({ where: { userId: tenant.id, title: 'Booking rejected' } });
      expect(rejectNotification.threadId).toBe(thread.id);
      await expect(chat.sendMessage(thread.id, landlord.id, UserRole.LANDLORD, { body: 'Hi' })).rejects.toThrow(ForbiddenException);
    });
  });

  // --- Support: auto-assignment, claims, transfers, history -----------------

  describe('support conversations', () => {
    async function customerSupportThread() {
      const customer = await makeUser(prisma, UserRole.LANDLORD);
      const thread = await chat.openSupportThread(customer.id, 'PAYMENTS');
      return { customer, thread };
    }

    it('auto-assigns to the online, on-duty admin with the fewest open chats', async () => {
      const busy = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT', fullName: 'Busy Admin' });
      const free = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT', fullName: 'Free Admin' });
      const away = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT', adminOnDuty: false });
      online.add(busy.id).add(free.id).add(away.id);
      await prisma.thread.create({ data: { isSupport: true, assignedAdminId: busy.id } });

      const { customer, thread } = await customerSupportThread();
      await chat.sendMessage(thread.id, customer.id, UserRole.LANDLORD, { body: 'My payout is late' });

      const updated = await prisma.thread.findUniqueOrThrow({ where: { id: thread.id } });
      expect(updated.assignedAdminId).toBe(free.id);
      expect(updated.supportTopic).toBe('PAYMENTS');
      const log = await prisma.threadTransferLog.findFirstOrThrow({ where: { threadId: thread.id } });
      expect(log.kind).toBe('AUTO_ASSIGN');
      // The assignee is notified like any participant.
      expect(await prisma.notification.count({ where: { userId: free.id, threadId: thread.id } })).toBe(1);
    });

    it('leaves the chat in the queue when nobody suitable is online, or auto-assign is off', async () => {
      const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const { customer, thread } = await customerSupportThread();
      await chat.sendMessage(thread.id, customer.id, UserRole.LANDLORD, { body: 'Hello?' });
      expect((await prisma.thread.findUniqueOrThrow({ where: { id: thread.id } })).assignedAdminId).toBeNull();

      online.add(admin.id);
      process.env.SUPPORT_AUTO_ASSIGN = 'false';
      await chat.sendMessage(thread.id, customer.id, UserRole.LANDLORD, { body: 'Anyone?' });
      expect((await prisma.thread.findUniqueOrThrow({ where: { id: thread.id } })).assignedAdminId).toBeNull();
    });

    it('records claim and transfer, posts a transfer notice, and limits history to handler and super admins', async () => {
      const ada = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT', fullName: 'Ada Obi' });
      const ben = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR', fullName: 'Ben Okafor' });
      const boss = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
      const { thread } = await customerSupportThread();

      await chat.claimThread(thread.id, ada.id);
      await chat.transferThread(thread.id, ada.id, ben.id);

      const notice = await prisma.message.findFirstOrThrow({ where: { threadId: thread.id, type: 'SYSTEM' } });
      expect(notice.body).toBe('This conversation has been transferred to Ben from HomeServant Support.');

      const history = await chat.getHandlingHistory(thread.id, ben.id);
      expect(history.firstHandler?.id).toBe(ada.id);
      expect(history.entries.map((e) => e.kind)).toEqual(['CLAIM', 'TRANSFER']);
      expect(history.currentAdmin?.id).toBe(ben.id);
      await expect(chat.getHandlingHistory(thread.id, boss.id)).resolves.toBeDefined();
      await expect(chat.getHandlingHistory(thread.id, ada.id)).rejects.toThrow(ForbiddenException);

      // The summary's "last transfer" ignores the claim entry.
      const summary = await chat.getThreadSummary(thread.id, ben.id, UserRole.ADMIN);
      expect(summary.lastTransfer?.fromAdmin?.id).toBe(ada.id);
    });

    it('keeps internal notes to the handling admin and super admins', async () => {
      const ada = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const other = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
      const boss = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
      const { thread } = await customerSupportThread();
      await chat.claimThread(thread.id, ada.id);

      await tools.addNote(thread.id, ada.id, 'Refund promised by Friday');
      await expect(tools.listNotes(thread.id, boss.id)).resolves.toHaveLength(1);
      await expect(tools.listNotes(thread.id, other.id)).rejects.toThrow(ForbiddenException);
      await expect(tools.triage(thread.id, other.id, undefined, 'URGENT')).rejects.toThrow(ForbiddenException);
      await expect(tools.triage(thread.id, ada.id, undefined, 'URGENT')).resolves.toMatchObject({ priority: 'URGENT' });
    });

    it('lets only the author or a moderator+ change a saved reply', async () => {
      const author = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const peer = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const moderator = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
      const reply = await tools.createSavedReply(author.id, 'Refunds', 'Refunds take 3-5 working days.');
      await expect(tools.updateSavedReply(reply.id, peer.id, 'x', 'y')).rejects.toThrow(ForbiddenException);
      await expect(tools.updateSavedReply(reply.id, moderator.id, 'Refunds', 'Updated')).resolves.toMatchObject({ body: 'Updated' });
    });

    it('lists every active admin with level, duty and load for transfers', async () => {
      const ada = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN', adminOnDuty: false });
      await prisma.thread.create({ data: { isSupport: true, assignedAdminId: ada.id } });
      online.add(ada.id);
      const targets = await tools.transferTargets();
      expect(targets).toHaveLength(2);
      expect(targets.find((t) => t.id === ada.id)).toMatchObject({ openChats: 1, isOnline: true, adminLevel: 'SUPPORT' });
    });
  });

  // --- Nobody available: the safety net --------------------------------------------

  describe('when no admin is available', () => {
    it('tells the customer once, then assigns the chat as soon as an admin comes online', async () => {
      const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const customer = await makeUser(prisma, UserRole.TENANT);
      const thread = await chat.openSupportThread(customer.id, 'BOOKING');
      await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Hello?' });
      await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Anyone there?' });
      const notices = await prisma.message.findMany({ where: { threadId: thread.id, type: 'SYSTEM' } });
      expect(notices).toHaveLength(1);
      expect(notices[0].body).toMatch(/No one from our support team is available right now/);

      online.add(admin.id);
      expect(await chat.assignWaitingQueue()).toBe(1);
      expect((await prisma.thread.findUniqueOrThrow({ where: { id: thread.id } })).assignedAdminId).toBe(admin.id);
      expect(await prisma.notification.count({ where: { userId: admin.id, title: 'A waiting conversation was assigned to you' } })).toBe(1);
    });

    it('emails every super admin once when a chat has been unclaimed for 15 minutes', async () => {
      const boss = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN' });
      const customer = await makeUser(prisma, UserRole.TENANT);
      const thread = await chat.openSupportThread(customer.id);
      await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Urgent' });
      await prisma.message.updateMany({ where: { threadId: thread.id }, data: { createdAt: new Date(Date.now() - 20 * 60_000) } });
      const config = { get: () => undefined };
      const alerts = new SupportAlertsService(prisma as never, notifications, config as never, chat, mail as never);

      await alerts.run();
      await alerts.run();
      const escalations = mail.sent.filter((m) => m.to === boss.email && m.subject.includes('nobody assigned'));
      expect(escalations).toHaveLength(1);
    });
  });

  // --- Support dashboard stats ---------------------------------------------------------

  describe('support stats and ratings', () => {
    it('records first response, transfers and resolution, and lets the customer rate once', async () => {
      const ada = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const ben = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const customer = await makeUser(prisma, UserRole.LANDLORD);
      const thread = await chat.openSupportThread(customer.id, 'LISTING');
      await chat.sendMessage(thread.id, customer.id, UserRole.LANDLORD, { body: 'My listing is hidden' });
      await chat.claimThread(thread.id, ada.id);
      await chat.sendMessage(thread.id, ada.id, UserRole.ADMIN, { body: 'Looking into it' });
      await chat.transferThread(thread.id, ada.id, ben.id);
      await expect(chat.rateSupportThread(thread.id, customer.id, 5)).rejects.toThrow(BadRequestException);
      await chat.resolveSupportThread(thread.id, ben.id);

      const summary = await chat.getThreadSummary(thread.id, customer.id, UserRole.LANDLORD);
      expect(summary.canRate).toBe(true);
      await chat.rateSupportThread(thread.id, customer.id, 4, 'Quick, thanks');
      await expect(chat.rateSupportThread(thread.id, customer.id, 1)).rejects.toThrow(BadRequestException);

      const stat = await prisma.supportChatStat.findUniqueOrThrow({ where: { threadId: thread.id } });
      expect(stat).toMatchObject({
        customerId: customer.id,
        customerRole: 'LANDLORD',
        topic: 'LISTING',
        firstResponderId: ada.id,
        currentAdminId: ben.id,
        transferCount: 1,
        resolvedById: ben.id,
        rating: 4,
        ratingComment: 'Quick, thanks',
      });
      expect(stat.firstCustomerMessageAt).not.toBeNull();
      expect(stat.firstResponseAt).not.toBeNull();
    });

    it('summarises the numbers for the dashboard', async () => {
      const ada = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT', fullName: 'Ada Obi' });
      online.add(ada.id);
      const customers = [await makeUser(prisma, UserRole.TENANT), await makeUser(prisma, UserRole.TENANT)];
      for (const [i, customer] of customers.entries()) {
        const thread = await chat.openSupportThread(customer.id, i === 0 ? 'PAYMENTS' : 'BOOKING');
        await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Help' });
        await chat.sendMessage(thread.id, ada.id, UserRole.ADMIN, { body: 'On it' });
        await chat.resolveSupportThread(thread.id, ada.id);
        await chat.rateSupportThread(thread.id, customer.id, i === 0 ? 5 : 3);
      }
      // One more waiting in the queue with nobody online.
      online.delete(ada.id);
      const waiting = await makeUser(prisma, UserRole.TENANT);
      const queued = await chat.openSupportThread(waiting.id);
      await chat.sendMessage(queued.id, waiting.id, UserRole.TENANT, { body: 'Hello?' });

      const m = await new SupportMetricsService(prisma as never, fakePresence(online) as never).metrics(30);
      expect(m.totals).toMatchObject({ conversations: 3, resolved: 2, averageRating: 4, ratings: 2, neverAnswered: 1 });
      expect(m.totals.medianFirstResponseMinutes).not.toBeNull();
      expect(m.live).toMatchObject({ waiting: 1, adminsAvailable: 0 });
      expect(m.byAdmin.find((a) => a.id === ada.id)).toMatchObject({ firstReplies: 2, resolved: 2, averageRating: 4 });
      expect(m.byTopic.map((t) => t.topic).sort()).toEqual(['BOOKING', 'PAYMENTS', 'UNSPECIFIED']);
      expect(m.byHour.reduce((a, b) => a + b, 0)).toBe(3);
      expect(m.byDay).toHaveLength(30);
      expect(m.recentRatings).toHaveLength(2);
    });
  });

  // --- Customer ends the chat -----------------------------------------------------------

  describe('customer ends a support chat', () => {
    it('closes it for both sides, tells the admin, and a new Contact Support starts fresh', async () => {
      const ada = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const customer = await makeUser(prisma, UserRole.TENANT);
      const thread = await chat.openSupportThread(customer.id, 'ACCOUNT');
      await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Hi' });
      await chat.claimThread(thread.id, ada.id);
      await chat.sendMessage(thread.id, ada.id, UserRole.ADMIN, { body: 'Hello, how can I help?' });

      const stranger = await makeUser(prisma, UserRole.TENANT);
      await expect(chat.endSupportThreadByCustomer(thread.id, stranger.id)).rejects.toThrow(/not found/);

      await chat.endSupportThreadByCustomer(thread.id, customer.id);
      await expect(chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Wait' })).rejects.toThrow(/has ended/);
      await expect(chat.sendMessage(thread.id, ada.id, UserRole.ADMIN, { body: 'Still there?' })).rejects.toThrow(/has ended/);

      const notice = await prisma.message.findFirst({ where: { threadId: thread.id, type: 'SYSTEM' }, orderBy: { createdAt: 'desc' } });
      expect(notice?.body).toBe('The customer ended this conversation.');
      expect(await prisma.notification.count({ where: { userId: ada.id, title: 'A customer ended their conversation' } })).toBe(1);
      const stat = await prisma.supportChatStat.findUniqueOrThrow({ where: { threadId: thread.id } });
      expect(stat).toMatchObject({ closedByCustomer: true, resolvedById: null });
      expect(stat.resolvedAt).not.toBeNull();
      // An admin replied, so they can rate it.
      expect((await chat.getThreadSummary(thread.id, customer.id, UserRole.TENANT)).canRate).toBe(true);

      const next = await chat.openSupportThread(customer.id);
      expect(next.id).not.toBe(thread.id);
    });

    it('does not ask for a rating when nobody replied', async () => {
      const customer = await makeUser(prisma, UserRole.TENANT);
      const thread = await chat.openSupportThread(customer.id);
      await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Hello?' });
      await chat.endSupportThreadByCustomer(thread.id, customer.id);
      expect((await chat.getThreadSummary(thread.id, customer.id, UserRole.TENANT)).canRate).toBe(false);
      await expect(chat.rateSupportThread(thread.id, customer.id, 2)).rejects.toThrow(BadRequestException);
      // It left the queue.
      expect(await chat.findSupportQueue()).toHaveLength(0);
    });
  });

  // --- Counts and read state --------------------------------------------------

  describe('read state and the admin Messages badge', () => {
    it('clears the reader\'s notifications for a chat when it is read, and the badge drops', async () => {
      const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPPORT' });
      const customer = await makeUser(prisma, UserRole.TENANT);
      const thread = await chat.openSupportThread(customer.id);
      await chat.claimThread(thread.id, admin.id);
      await chat.sendMessage(thread.id, customer.id, UserRole.TENANT, { body: 'Help please' });
      // A second, untouched chat still waiting in the queue.
      const other = await makeUser(prisma, UserRole.TENANT);
      await chat.openSupportThread(other.id);

      // messagesAttentionCount only touches the database.
      const adminService = new (AdminService as unknown as new (...args: unknown[]) => AdminService)(prisma);
      expect(await adminService.messagesAttentionCount(admin.id)).toBe(2);
      expect(await prisma.notification.count({ where: { userId: admin.id, threadId: thread.id, readAt: null } })).toBe(1);

      await chat.markRead(thread.id, admin.id, UserRole.ADMIN);
      expect(await prisma.notification.count({ where: { userId: admin.id, threadId: thread.id, readAt: null } })).toBe(0);
      expect(await adminService.messagesAttentionCount(admin.id)).toBe(1);
    });
  });

  // --- Unread-message emails ----------------------------------------------------

  describe('unread-message emails', () => {
    it('emails the recipient once, 15 minutes after an unread message', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      const thread = await chat.findOrCreateThread(landlord.id, { recipientId: tenant.id, propertyId: property.id });
      const message = await chat.sendMessage(thread.id, landlord.id, UserRole.LANDLORD, { body: 'Viewing on Saturday?' });
      const config = { get: (key: string) => (key === 'APP_URL' ? 'https://app.example' : undefined) };
      const emails = new UnreadMessageEmailService(prisma as never, mail as never, config as never);

      const tooSoon = new Date(message.createdAt.getTime() + 5 * 60_000);
      expect(await emails.run(tooSoon)).toBe(0);

      const later = new Date(message.createdAt.getTime() + 16 * 60_000);
      expect(await emails.run(later)).toBe(1);
      expect(mail.sent[0].to).toBe(tenant.email);
      expect(mail.sent[0].text).toContain('Viewing on Saturday?');
      expect(await emails.run(later)).toBe(0);
    });

    it('does not email about messages that were read', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      const thread = await chat.findOrCreateThread(landlord.id, { recipientId: tenant.id, propertyId: property.id });
      const message = await chat.sendMessage(thread.id, landlord.id, UserRole.LANDLORD, { body: 'Hi' });
      await prisma.booking.create({ data: { propertyId: property.id, tenantId: tenant.id, status: 'PAID_AWAITING_INSPECTION' } });
      await chat.markRead(thread.id, tenant.id, UserRole.TENANT);
      const emails = new UnreadMessageEmailService(prisma as never, mail as never, { get: () => undefined } as never);
      expect(await emails.run(new Date(message.createdAt.getTime() + 20 * 60_000))).toBe(0);
    });
  });

  // --- Admin accounts ---------------------------------------------------------------

  describe('admin accounts', () => {
    it('records which super admin created an admin', async () => {
      const boss = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'SUPER_ADMIN', fullName: 'Chidi Eze' });
      await prisma.pendingAdmin.create({
        data: { email: 'new.admin@test.local', fullName: 'New Admin', level: 'SUPPORT', tempPasswordHash: 'x', invitedById: boss.id },
      });
      const otp = { verify: async () => undefined };
      const admin = new (AdminService as unknown as new (...args: unknown[]) => AdminService)(
        prisma, null, mail, null, otp, null, null, null, gateway,
      );
      const created = await admin.confirmAdminOtp({ email: 'new.admin@test.local', code: '1234' });
      expect(created.createdByAdmin).toMatchObject({ id: boss.id, fullName: 'Chidi Eze' });
      const listed = await admin.findAdmins();
      expect(listed.find((a) => a.id === created.id)?.createdByAdmin?.id).toBe(boss.id);
    });
  });

  // --- Listing deletion ------------------------------------------------------------

  describe('deleting a listing', () => {
    function propertiesService() {
      return new PropertiesService(prisma as never, {} as never, {} as never, { requireVerifiedLandlords: async () => false } as never, { create: async () => undefined } as never);
    }

    it('refuses while a tenant lives there, and allows it once the lease has ended', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      const booking = await prisma.booking.create({
        data: { propertyId: property.id, tenantId: tenant.id, status: 'MOVED_IN', leaseEndDate: new Date(Date.now() + 86_400_000) },
      });
      await expect(propertiesService().remove(property.id, landlord.id)).rejects.toThrow(/occupied/);
      await prisma.booking.update({ where: { id: booking.id }, data: { leaseEndDate: new Date(Date.now() - 86_400_000) } });
      await expect(propertiesService().remove(property.id, landlord.id)).resolves.toBeUndefined();
    });

    it('refuses while a tenant\'s payment is held before move-in', async () => {
      const { tenant, landlord, property } = await tenantLandlordProperty();
      await prisma.booking.create({ data: { propertyId: property.id, tenantId: tenant.id, status: 'INSPECTION_CONFIRMED' } });
      await expect(propertiesService().remove(property.id, landlord.id)).rejects.toThrow(BadRequestException);
    });

    it('refuses another landlord', async () => {
      const { property } = await tenantLandlordProperty();
      const stranger = await makeUser(prisma, UserRole.LANDLORD);
      await expect(propertiesService().remove(property.id, stranger.id)).rejects.toThrow(ForbiddenException);
    });
  });
});
