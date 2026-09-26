import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ActivityLogType, MessageType, NotificationType, Prisma, UserRole } from '@prisma/client';
import { ActivityLogService } from '../activity-log/activity-log.service';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { ChatGateway } from './chat.gateway';
import { CreateThreadDto } from './dto/create-thread.dto';
import { SendMessageDto } from './dto/send-message.dto';
import { PresenceService } from './presence.service';

const MESSAGE_PAGE_SIZE = 50;
const CHAT_LOG_WINDOW_DAYS = 30;

@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
    private readonly presence: PresenceService,
    private readonly gateway: ChatGateway,
    private readonly activityLog: ActivityLogService,
    private readonly storage: StorageService,
  ) {}

  /// Reuses an existing thread between the same two people about the same
  /// property/order (both `undefined`/`null` counts as a match) instead of
  /// creating a new one every time "Message Landlord" — or, for a
  /// marketplace pickup order, "Message Vendor"/"Message Customer" — is
  /// tapped again.
  async findOrCreateThread(userId: string, dto: CreateThreadDto) {
    if (dto.recipientId === userId) {
      throw new ForbiddenException('Cannot start a thread with yourself');
    }

    const recipient = await this.prisma.user.findUnique({ where: { id: dto.recipientId }, select: { id: true } });
    if (!recipient) throw new NotFoundException('Recipient not found');

    const existing = await this.prisma.thread.findFirst({
      where: {
        propertyId: dto.propertyId ?? null,
        orderId: dto.orderId ?? null,
        AND: [
          { participants: { some: { userId } } },
          { participants: { some: { userId: dto.recipientId } } },
        ],
      },
      include: { participants: true },
    });
    if (existing) return existing;

    return this.prisma.thread.create({
      data: {
        propertyId: dto.propertyId,
        orderId: dto.orderId,
        participants: { create: [{ userId }, { userId: dto.recipientId }] },
      },
      include: { participants: true },
    });
  }

  /// [isAdmin] hides a resolved support thread from a non-admin caller's
  /// own inbox (the "cleared... once the issue is tagged resolved" rule)
  /// while an admin still sees it — the 30-day cleanup cron is what
  /// eventually removes it for everyone, not this.
  async findForUser(userId: string, isAdmin: boolean) {
    const threads = await this.prisma.thread.findMany({
      where: {
        participants: { some: { userId } },
        ...(isAdmin ? {} : { NOT: { isSupport: true, status: 'RESOLVED' } }),
      },
      include: {
        participants: { include: { user: { select: { id: true, fullName: true, profilePhotoUrl: true, lastActiveAt: true } } } },
        property: { select: { id: true, title: true, imageUrl: true } },
        order: { select: { id: true, items: { take: 1, select: { productName: true } } } },
        messages: { orderBy: { createdAt: 'desc' }, take: 1 },
      },
      orderBy: { updatedAt: 'desc' },
    });

    const unreadCounts = await this.prisma.message.groupBy({
      by: ['threadId'],
      where: { threadId: { in: threads.map((t) => t.id) }, senderId: { not: userId }, readAt: null },
      _count: true,
    });
    const unreadByThread = new Map(unreadCounts.map((u) => [u.threadId, u._count]));

    return threads.map((thread) => ({
      id: thread.id,
      property: thread.property,
      order: thread.order ? { id: thread.order.id, productName: thread.order.items[0]?.productName ?? null } : null,
      otherParticipants: thread.participants
        .filter((p) => p.userId !== userId)
        .map((p) => ({
          id: p.user.id,
          fullName: p.user.fullName,
          profilePhotoUrl: p.user.profilePhotoUrl,
          isOnline: this.presence.isOnline(p.user.id),
          lastActiveAt: p.user.lastActiveAt,
        })),
      lastMessage: thread.messages[0] ?? null,
      unreadCount: unreadByThread.get(thread.id) ?? 0,
      updatedAt: thread.updatedAt,
      isSupport: thread.isSupport,
      resolved: thread.status === 'RESOLVED',
    }));
  }

  /// Finds-or-creates the calling user's own "Contact Support" thread —
  /// unlike [findOrCreateThread], this takes no `recipientId`: a support
  /// thread starts with only the user as a participant and is visible to
  /// every admin via [findSupportQueue] until one of them replies (see
  /// [sendMessage]'s auto-claim), at which point that admin becomes a real
  /// participant too. Reopens the same thread on a repeat visit as long as
  /// it's still OPEN; a RESOLVED one gets a fresh thread instead, so an old
  /// closed conversation doesn't reopen just because the user tapped "Live
  /// Chat" again.
  async openSupportThread(userId: string) {
    // Serializable, not the default isolation level, so a double-tap (two
    // calls landing at nearly the same moment) can't both see "no existing
    // thread" and both create one — Postgres aborts the loser with a
    // serialization failure instead of letting it silently create a
    // duplicate OPEN support thread for the same user.
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          const existing = await tx.thread.findFirst({
            where: { isSupport: true, status: 'OPEN', participants: { some: { userId } } },
            include: { participants: true },
          });
          if (existing) return existing;
          return tx.thread.create({
            data: { isSupport: true, participants: { create: [{ userId }] } },
            include: { participants: true },
          });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2034') {
        // Lost the race — the other call's thread already exists now.
        const existing = await this.prisma.thread.findFirst({
          where: { isSupport: true, status: 'OPEN', participants: { some: { userId } } },
          orderBy: { createdAt: 'asc' },
          include: { participants: true },
        });
        if (existing) return existing;
      }
      throw error;
    }
  }

  /// Every admin's shared queue — open, *unclaimed* support threads, oldest
  /// first (so the longest-waiting user is handled first). The moment any
  /// admin claims one (opening it from this queue, or being first to reply
  /// — see [claimThread]/[attemptClaim]) it drops out of here and into that
  /// admin's own inbox instead ([findForUser]); this is what keeps the
  /// queue down to only truly unattended tickets. Not restricted to
  /// threads the calling admin happens to be a participant of, unlike
  /// [findForUser] — that's the whole point of a shared queue.
  async findSupportQueue() {
    const threads = await this.prisma.thread.findMany({
      where: { isSupport: true, status: 'OPEN', assignedAdminId: null },
      include: {
        participants: { include: { user: { select: { id: true, fullName: true, profilePhotoUrl: true } } } },
        messages: { orderBy: { createdAt: 'desc' }, take: 1 },
      },
      orderBy: { createdAt: 'asc' },
    });
    return threads.map((thread) => ({
      id: thread.id,
      assignedAdminId: thread.assignedAdminId,
      requester: thread.participants.find((p) => p.userId !== thread.assignedAdminId)?.user ?? null,
      lastMessage: thread.messages[0] ?? null,
      createdAt: thread.createdAt,
      updatedAt: thread.updatedAt,
    }));
  }

  /// Every support thread from the last [CHAT_LOG_WINDOW_DAYS] days,
  /// regardless of who (if anyone) claimed it or whether it's resolved —
  /// the super-admin-only "Chat Log" audit view. The window mirrors (and is
  /// belt-and-suspenders with) SupportChatCleanupService's own 30-day purge,
  /// which already means nothing older ever survives to be queried here.
  /// [transferChain] lists every admin who has ever held this thread, in
  /// order, distinct from [Thread.assignedAdminId] which only ever holds
  /// the *current* one.
  async findChatLog() {
    const cutoff = new Date(Date.now() - CHAT_LOG_WINDOW_DAYS * 24 * 60 * 60 * 1000);
    const threads = await this.prisma.thread.findMany({
      where: { isSupport: true, createdAt: { gte: cutoff } },
      include: {
        participants: { include: { user: { select: { id: true, fullName: true } } } },
        assignedAdmin: { select: { id: true, fullName: true } },
        transferLogs: {
          orderBy: { createdAt: 'asc' },
          include: { fromAdmin: { select: { fullName: true } }, toAdmin: { select: { fullName: true } } },
        },
        messages: { orderBy: { createdAt: 'desc' }, take: 1 },
      },
      orderBy: { createdAt: 'desc' },
    });
    return threads.map((thread) => {
      const chain = [
        thread.transferLogs[0]?.fromAdmin?.fullName,
        ...thread.transferLogs.map((log) => log.toAdmin?.fullName),
      ].filter((name): name is string => Boolean(name));
      return {
        id: thread.id,
        requester: thread.participants.find((p) => p.userId !== thread.assignedAdminId)?.user ?? null,
        currentAdmin: thread.assignedAdmin,
        status: thread.status === 'RESOLVED' ? 'RESOLVED' : thread.assignedAdminId ? 'OPENED' : 'UNATTENDED',
        transferChain: chain,
        lastMessage: thread.messages[0] ?? null,
        createdAt: thread.createdAt,
        resolvedAt: thread.resolvedAt,
      };
    });
  }

  /// Claims an unattended support thread for [adminId] — the explicit
  /// counterpart to [sendMessage]'s implicit "first reply claims it": this
  /// is what fires the moment an admin *opens* a ticket from the Support
  /// Queue, before they've necessarily typed anything, which is what
  /// actually moves it into their inbox and off every other admin's queue.
  /// Refuses a thread that's already resolved (nothing left to claim) or
  /// already claimed by someone else (loses the race, see [attemptClaim]).
  async claimThread(threadId: string, adminId: string): Promise<void> {
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });
    if (!thread || !thread.isSupport) throw new NotFoundException('Support thread not found');
    if (thread.status === 'RESOLVED') throw new ForbiddenException('This conversation is already resolved');
    if (thread.assignedAdminId === adminId) return;

    const claimed = await this.attemptClaim(threadId, adminId);
    if (!claimed) throw new ForbiddenException('This conversation has already been claimed by another admin');

    await this.activityLog.log(ActivityLogType.SUPPORT_THREAD_CLAIMED, { actorId: adminId });
    this.gateway.broadcastToAdmins('thread:claimed', { threadId });
  }

  /// Race-safe "claim this unattended support thread" primitive shared by
  /// [claimThread] (an explicit open from the Support Queue) and
  /// [sendMessage] (an implicit claim via first reply). The conditional
  /// `updateMany` (not a plain read-then-write) is what makes it race-safe:
  /// two admins racing for the same thread can't both win it — Postgres
  /// row-locks the UPDATE, so only whichever one still finds
  /// `assignedAdminId: null` true when it actually runs gets `count: 1`;
  /// the loser gets `count: 0` and is told it lost rather than silently
  /// double-claiming.
  private async attemptClaim(threadId: string, adminId: string): Promise<boolean> {
    const claim = await this.prisma.thread.updateMany({
      where: { id: threadId, assignedAdminId: null },
      data: { assignedAdminId: adminId },
    });
    if (claim.count === 0) return false;
    await this.prisma.threadParticipant.create({ data: { threadId, userId: adminId } });
    return true;
  }

  /// Sets `status: RESOLVED` — from that point [findForUser] hides this
  /// thread from the *user's* inbox (see its `isAdmin` param); the admin
  /// side still shows it until the 30-day cleanup cron purges it. Any admin
  /// can resolve it, not just whoever's assigned, same as any admin can
  /// see the shared queue. [adminId] is only used for the activity-log
  /// entry — it plays no part in authorization.
  async resolveSupportThread(threadId: string, adminId: string): Promise<void> {
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId }, include: { participants: true } });
    if (!thread || !thread.isSupport) throw new NotFoundException('Support thread not found');
    if (thread.status === 'RESOLVED') return;
    await this.prisma.thread.update({ where: { id: threadId }, data: { status: 'RESOLVED', resolvedAt: new Date() } });
    await this.activityLog.log(ActivityLogType.SUPPORT_THREAD_RESOLVED, { actorId: adminId });

    const requester = thread.participants.find((p) => p.userId !== thread.assignedAdminId);
    if (requester) {
      await this.notifications.create(
        requester.userId,
        NotificationType.SUPPORT_THREAD_RESOLVED,
        'Your support conversation was resolved',
        "An admin marked your support conversation as resolved. Reach out again any time if you still need help.",
      );
    }
  }

  async findMessages(threadId: string, userId: string, senderRole?: UserRole, before?: string) {
    await this.assertParticipant(threadId, userId, senderRole);
    const messages = await this.prisma.message.findMany({
      where: { threadId, ...(before ? { createdAt: { lt: new Date(before) } } : {}) },
      orderBy: { createdAt: 'desc' },
      take: MESSAGE_PAGE_SIZE,
      include: { sender: { select: { id: true, fullName: true } } },
    });
    return messages.reverse();
  }

  async sendMessage(threadId: string, userId: string, senderRole: UserRole, dto: SendMessageDto) {
    await this.assertParticipant(threadId, userId, senderRole);
    const body = dto.body?.trim() ?? '';
    if (!body && !dto.attachmentUrl) {
      throw new BadRequestException('A message needs either text or an image');
    }
    if (dto.attachmentUrl) {
      await this.storage.assertIsOwnImage(dto.attachmentUrl);
    }
    // Falls back to a fixed label rather than the (possibly empty) body —
    // an image sent with no caption would otherwise show as a blank
    // notification/support-queue preview.
    const previewText = body || '📷 Photo';
    const [message] = await this.prisma.$transaction([
      this.prisma.message.create({
        data: {
          threadId,
          senderId: userId,
          body,
          type: dto.attachmentUrl ? MessageType.IMAGE : MessageType.TEXT,
          attachmentUrl: dto.attachmentUrl,
        },
        include: { sender: { select: { id: true, fullName: true } } },
      }),
      this.prisma.thread.update({ where: { id: threadId }, data: { updatedAt: new Date() } }),
    ]);
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });

    // First admin to reply to an unclaimed support thread claims it — the
    // implicit counterpart to [claimThread]'s explicit "open it from the
    // queue" claim, for whenever an admin replies without having opened it
    // that way first (e.g. an old client, or a reply typed from a
    // notification deep-link). See [attemptClaim] for the race-safety.
    if (senderRole === 'ADMIN' && thread?.isSupport && !thread.assignedAdminId) {
      const claimed = await this.attemptClaim(threadId, userId);
      if (claimed) {
        await this.activityLog.log(ActivityLogType.SUPPORT_THREAD_CLAIMED, { actorId: userId });
        this.gateway.broadcastToAdmins('thread:claimed', { threadId });
      }
    }

    const otherParticipants = await this.prisma.threadParticipant.findMany({
      where: { threadId, userId: { not: userId } },
      select: { userId: true },
    });
    const senderName = message.sender?.fullName ?? 'Someone';
    await Promise.all(
      otherParticipants.map((p) =>
        this.notifications.create(
          p.userId,
          NotificationType.NEW_MESSAGE,
          `New message from ${senderName}`,
          previewText.length > 140 ? `${previewText.slice(0, 140)}…` : previewText,
        ),
      ),
    );

    // An unclaimed support thread has no admin participant for the loop
    // above to notify — without this, a brand-new "Contact Support"
    // message (or any message on it before an admin picks it up) alerted
    // nobody until an admin happened to manually reopen the Support Queue
    // tab, which defeated the point of this whole feature.
    if (senderRole !== 'ADMIN' && thread?.isSupport && otherParticipants.length === 0) {
      const admins = await this.prisma.user.findMany({ where: { role: 'ADMIN' }, select: { id: true } });
      await Promise.all(
        admins.map((admin) =>
          this.notifications.create(
            admin.id,
            NotificationType.NEW_MESSAGE,
            'New support conversation',
            `${senderName}: ${previewText.length > 140 ? `${previewText.slice(0, 140)}…` : previewText}`,
          ),
        ),
      );
      this.gateway.broadcastToAdmins('message:new', { threadId, message });
    }

    return message;
  }

  async markRead(threadId: string, userId: string, senderRole?: UserRole): Promise<void> {
    await this.assertParticipant(threadId, userId, senderRole);
    await this.prisma.message.updateMany({
      where: { threadId, senderId: { not: userId }, readAt: null },
      data: { readAt: new Date() },
    });
  }

  /// Used by ChatController to know which sockets to push a just-sent
  /// message to (see ChatGateway.broadcastMessage) — kept separate from
  /// [sendMessage]'s own return value so the REST response shape (just
  /// the created Message) doesn't change for existing API consumers.
  async participantIds(threadId: string): Promise<string[]> {
    const participants = await this.prisma.threadParticipant.findMany({ where: { threadId }, select: { userId: true } });
    return participants.map((p) => p.userId);
  }

  /// [senderRole] lets any admin read/reply to an unclaimed support thread
  /// even before they're a [ThreadParticipant] of it (see [sendMessage]'s
  /// auto-claim, which is what actually adds them as one) — every other
  /// thread, and every other role, still requires real participancy.
  private async assertParticipant(threadId: string, userId: string, senderRole?: UserRole): Promise<void> {
    const membership = await this.prisma.threadParticipant.findUnique({
      where: { threadId_userId: { threadId, userId } },
    });
    if (membership) return;
    if (senderRole === 'ADMIN') {
      const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });
      if (thread?.isSupport) return;
    }
    throw new ForbiddenException('Not a participant of this thread');
  }

  /// Hands a console conversation off to another admin, "the way Namecheap
  /// support does it" — [fromAdminId] must actually be in this thread
  /// (so an admin can only transfer conversations they're personally
  /// part of, not any thread by id) and [toAdminId] must be an admin
  /// account. Refuses once the thread's been marked resolved — there's
  /// nothing left to hand off. Swaps the ThreadParticipant row's `userId`
  /// in place rather than delete+recreate, so message history/read state
  /// is unaffected; also moves `assignedAdminId` to [toAdminId] (it's meant
  /// to track *current* handler, used by the queue/badge logic) and records
  /// a [ThreadTransferLog] row so the super-admin Chat Log can show the
  /// full chain later, since `assignedAdminId` itself only ever holds the
  /// latest one.
  async transferThread(threadId: string, fromAdminId: string, toAdminId: string): Promise<void> {
    if (fromAdminId === toAdminId) throw new ForbiddenException("Can't transfer a thread to yourself");
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });
    if (!thread) throw new NotFoundException('Thread not found');
    if (thread.status === 'RESOLVED') throw new ForbiddenException("Can't transfer a resolved conversation");

    const membership = await this.prisma.threadParticipant.findUnique({
      where: { threadId_userId: { threadId, userId: fromAdminId } },
    });
    if (!membership) throw new ForbiddenException('Not a participant of this thread');

    const toAdmin = await this.prisma.user.findUnique({ where: { id: toAdminId } });
    if (!toAdmin || toAdmin.role !== 'ADMIN') throw new NotFoundException('Admin not found');
    const alreadyIn = await this.prisma.threadParticipant.findUnique({
      where: { threadId_userId: { threadId, userId: toAdminId } },
    });
    if (alreadyIn) throw new ForbiddenException('That admin is already part of this conversation');

    await this.prisma.$transaction([
      this.prisma.threadParticipant.update({ where: { id: membership.id }, data: { userId: toAdminId } }),
      this.prisma.thread.update({ where: { id: threadId }, data: { assignedAdminId: toAdminId } }),
      this.prisma.threadTransferLog.create({ data: { threadId, fromAdminId, toAdminId } }),
    ]);
    await this.activityLog.log(ActivityLogType.SUPPORT_THREAD_TRANSFERRED, { actorId: fromAdminId, targetId: toAdminId });

    await this.notifications.create(
      toAdminId,
      NotificationType.THREAD_TRANSFERRED,
      'A conversation was transferred to you',
      'Another admin handed off a console conversation to you.',
    );
    await this.mail.send(
      toAdmin.email,
      'A HomeServant conversation was transferred to you',
      '<p>Another admin handed off a console conversation to you — open Messages in the admin console to continue it.</p>',
      'Another admin handed off a console conversation to you — open Messages in the admin console to continue it.',
    );
  }
}
