import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ActivityLogType, BookingStatus, MessageType, NotificationType, PaymentStatus, Prisma, SupportTopic, UserRole } from '@prisma/client';
import { ActivityLogService } from '../activity-log/activity-log.service';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { ChatGateway } from './chat.gateway';
import { CreateThreadDto } from './dto/create-thread.dto';
import { SendMessageDto } from './dto/send-message.dto';
import { PresenceService } from './presence.service';
import { adminCanAccessSupportThread } from './support-access';
import { adminPublicName } from '../common/admin-display-name';

const MESSAGE_PAGE_SIZE = 50;
const CHAT_LOG_WINDOW_DAYS = 30;

/// Booking statuses that mean the tenant has actually paid — the gate for
/// tenant/landlord messaging (see [ChatService.landlordTenantBlockReason]).
/// Mirrors `_paidBookingStatuses` in the Flutter property detail screen.
const PAID_BOOKING_STATUSES: BookingStatus[] = [
  BookingStatus.PAID,
  BookingStatus.PAID_AWAITING_INSPECTION,
  BookingStatus.INSPECTION_PROPOSED,
  BookingStatus.INSPECTION_CONFIRMED,
  BookingStatus.MOVED_IN,
];

/// How a support topic reads in admin alerts — matches the app's labels.
const SUPPORT_TOPIC_LABEL: Record<SupportTopic, string> = {
  PAYMENTS: 'Payments',
  BOOKING: 'Booking',
  ACCOUNT: 'Account',
  LISTING: 'Listing',
  MARKETPLACE: 'Marketplace',
  OTHER: 'Other',
};

const NOBODY_AVAILABLE_PREFIX = 'Thanks for your message.';

const PAYMENT_REQUIRED_MESSAGE = 'You can message the landlord once you have paid for this property';
const REFUNDED_MESSAGE =
  'This conversation was closed because the booking was refunded. It reopens if the tenant pays again.';

/// The tenant and landlord in a two-person, non-support, non-order thread
/// — the only kind of thread the payment rules apply to.
type LandlordTenantPair = { tenantId: string; landlordId: string };

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

    const [caller, recipient] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: userId }, select: { role: true } }),
      this.prisma.user.findUnique({ where: { id: dto.recipientId }, select: { id: true, role: true } }),
    ]);
    if (!recipient) throw new NotFoundException('Recipient not found');
    const pair = dto.orderId ? null : this.asLandlordTenantPair([
      { id: userId, role: caller?.role },
      { id: recipient.id, role: recipient.role },
    ]);

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
    // An existing thread still opens when messaging is closed, so its
    // history stays readable (sendMessage and the summary's canReply are
    // what stop new messages); only starting a new one is refused here.
    if (existing) return existing;
    if (pair) {
      const reason = await this.landlordTenantBlockReason(pair, userId, dto.propertyId ?? null);
      if (reason) throw new ForbiddenException(reason);
    }

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
        participants: {
          include: {
            user: { select: { id: true, fullName: true, firstName: true, role: true, profilePhotoUrl: true, lastActiveAt: true } },
          },
        },
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
          // Customers only ever see a support admin's first name.
          fullName: !isAdmin && p.user.role === UserRole.ADMIN ? adminPublicName(p.user) : p.user.fullName,
          profilePhotoUrl: p.user.profilePhotoUrl,
          isOnline: this.presence.isOnline(p.user.id),
          lastActiveAt: p.user.lastActiveAt,
        })),
      lastMessage: thread.messages[0] ?? null,
      unreadCount: unreadByThread.get(thread.id) ?? 0,
      updatedAt: thread.updatedAt,
      isSupport: thread.isSupport,
      resolved: thread.status === 'RESOLVED',
      supportTopic: thread.supportTopic,
      priority: thread.priority,
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
  async openSupportThread(userId: string, topic?: SupportTopic) {
    const caller = await this.prisma.user.findUnique({ where: { id: userId }, select: { role: true } });
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
          if (existing) {
            // The topic just picked is what they're getting in touch about
            // now — it replaces whatever the open conversation had, so the
            // admin sees the current reason rather than a stale one.
            if (topic && existing.supportTopic !== topic) {
              await tx.supportChatStat.updateMany({ where: { threadId: existing.id }, data: { topic } });
              return tx.thread.update({ where: { id: existing.id }, data: { supportTopic: topic }, include: { participants: true } });
            }
            return existing;
          }
          const created = await tx.thread.create({
            data: { isSupport: true, supportTopic: topic, participants: { create: [{ userId }] } },
            include: { participants: true },
          });
          // The dashboard's record of this conversation (see SupportChatStat).
          await tx.supportChatStat.create({
            data: { threadId: created.id, customerId: userId, customerRole: caller?.role, topic },
          });
          return created;
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
      // Most urgent first, then oldest first within a priority.
      orderBy: [{ priority: 'desc' }, { createdAt: 'asc' }],
    });
    return threads.map((thread) => ({
      id: thread.id,
      supportTopic: thread.supportTopic,
      priority: thread.priority,
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
    await this.notifications.clearThreadAlertsForOtherAdmins(threadId, adminId);
    this.gateway.broadcastToAdmins('thread:claimed', { threadId });
    await this.gateway.evictUnauthorizedFromThread(threadId);
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
  private async attemptClaim(
    threadId: string,
    adminId: string,
    kind: 'CLAIM' | 'AUTO_ASSIGN' = 'CLAIM',
  ): Promise<boolean> {
    const claim = await this.prisma.thread.updateMany({
      where: { id: threadId, assignedAdminId: null },
      data: { assignedAdminId: adminId },
    });
    if (claim.count === 0) return false;
    await this.prisma.$transaction([
      this.prisma.threadParticipant.create({ data: { threadId, userId: adminId } }),
      // Recorded so the handling history can say who first took it up.
      this.prisma.threadTransferLog.create({
        data: { threadId, toAdminId: adminId, actorId: kind === 'CLAIM' ? adminId : null, kind },
      }),
      this.prisma.supportChatStat.updateMany({ where: { threadId }, data: { currentAdminId: adminId } }),
    ]);
    return true;
  }

  /// Sets `status: RESOLVED` — from that point [findForUser] hides this
  /// thread from the *user's* inbox (see its `isAdmin` param); the admin
  /// side still shows it until the 30-day cleanup cron purges it. Only the
  /// admin handling it can resolve it, or any admin while it's still
  /// unclaimed (see [canWrite]). A SUPER_ADMIN viewing someone else's
  /// conversation is read-only and can't resolve it.
  async resolveSupportThread(threadId: string, adminId: string): Promise<void> {
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId }, include: { participants: true } });
    if (!thread || !thread.isSupport) throw new NotFoundException('Support thread not found');
    if (!(await this.canWrite(threadId, adminId, UserRole.ADMIN))) {
      throw new ForbiddenException('Another admin is handling this conversation');
    }
    if (thread.status === 'RESOLVED') return;
    const resolvedAt = new Date();
    await this.prisma.$transaction([
      this.prisma.thread.update({ where: { id: threadId }, data: { status: 'RESOLVED', resolvedAt } }),
      this.prisma.supportChatStat.updateMany({ where: { threadId }, data: { resolvedAt, resolvedById: adminId } }),
    ]);
    await this.activityLog.log(ActivityLogType.SUPPORT_THREAD_RESOLVED, { actorId: adminId });

    const requester = thread.participants.find((p) => p.userId !== thread.assignedAdminId);
    if (requester) {
      await this.notifications.create(
        requester.userId,
        NotificationType.SUPPORT_THREAD_RESOLVED,
        'Your support conversation was resolved',
        'An admin marked your support conversation as resolved. Tap to rate how we did — and reach out again any time.',
        threadId,
      );
    }
  }

  /// Where a thread stands *now*, for the caller — what the client shows
  /// when someone opens a chat notification: still waiting for an admin,
  /// being handled (by them or by whom), transferred away, or resolved,
  /// and whether they can open it ([canView]) and reply ([canReply]).
  /// Visible to participants, to admins allowed into a support thread (see
  /// adminCanAccessSupportThread), and to an admin who transferred the
  /// thread away — they get the status (so their notification can say where
  /// it went) but canView false, since it's no longer theirs to read.
  /// The property a tenant–landlord chat is about, with its details, once
  /// the tenant in it has paid for it (any booking from payment through
  /// move-in, or a paid shortlet). Null otherwise.
  private async paidBookingProperty(thread: { isSupport: boolean; propertyId: string | null; participants: { userId: string }[] }) {
    if (thread.isSupport || !thread.propertyId) return null;
    const booking = await this.prisma.booking.findFirst({
      where: {
        propertyId: thread.propertyId,
        tenantId: { in: thread.participants.map((p) => p.userId) },
        status: {
          in: [
            BookingStatus.PAID,
            BookingStatus.PAID_AWAITING_INSPECTION,
            BookingStatus.INSPECTION_PROPOSED,
            BookingStatus.INSPECTION_CONFIRMED,
            BookingStatus.MOVED_IN,
          ],
        },
      },
      orderBy: { createdAt: 'desc' },
      select: {
        status: true,
        property: {
          select: {
            id: true,
            listingNumber: true,
            title: true,
            location: true,
            state: true,
            category: true,
            price: true,
            priceUnit: true,
            bedrooms: true,
            bathrooms: true,
            description: true,
            imageUrl: true,
            galleryUrls: true,
            unitAddress: true,
            roomNumber: true,
          },
        },
      },
    });
    return booking ? { ...booking.property, bookingStatus: booking.status } : null;
  }

  async getThreadSummary(threadId: string, userId: string, role: UserRole) {
    const thread = await this.prisma.thread.findUnique({
      where: { id: threadId },
      include: {
        participants: {
          include: { user: { select: { id: true, fullName: true, firstName: true, role: true, profilePhotoUrl: true } } },
        },
        assignedAdmin: { select: { id: true, fullName: true, firstName: true } },
        transferLogs: {
          where: { kind: { notIn: ['CLAIM', 'AUTO_ASSIGN'] } },
          orderBy: { createdAt: 'desc' },
          take: 1,
          include: { fromAdmin: { select: { id: true, fullName: true } }, toAdmin: { select: { id: true, fullName: true } } },
        },
      },
    });
    if (!thread) throw new NotFoundException('This conversation no longer exists');

    const isAdmin = role === UserRole.ADMIN;
    const isParticipant = thread.participants.some((p) => p.userId === userId);
    const transferredByMe =
      isAdmin &&
      (await this.prisma.threadTransferLog.count({ where: { threadId, fromAdminId: userId } })) > 0;
    const canView = isParticipant || (isAdmin && (await adminCanAccessSupportThread(this.prisma, thread, userId)));
    if (!canView && !transferredByMe) throw new ForbiddenException('Not a participant of this thread');

    const resolved = thread.status === 'RESOLVED';
    const unclaimedSupport = thread.isSupport && !thread.assignedAdminId;
    const lockedReason = isParticipant && !isAdmin ? await this.threadBlockReason(threadId, userId) : null;
    const lastTransfer = thread.transferLogs[0];
    const bookedProperty = isParticipant && !isAdmin ? await this.paidBookingProperty(thread) : null;
    // Customers only ever see a support admin's first name.
    const publicPerson = (u: { id: string; fullName: string | null; firstName: string | null; role?: UserRole; profilePhotoUrl?: string | null }) => ({
      id: u.id,
      fullName: !isAdmin && (u.role === undefined || u.role === UserRole.ADMIN) ? adminPublicName(u) : u.fullName,
      ...(u.profilePhotoUrl !== undefined ? { profilePhotoUrl: u.profilePhotoUrl } : {}),
    });
    return {
      id: thread.id,
      isSupport: thread.isSupport,
      // Set in a tenant–landlord chat about a property the tenant has paid
      // for: the app pins a preview of it (with a View property pop-up)
      // for both of them.
      bookedProperty,
      supportTopic: thread.supportTopic,
      priority: thread.priority,
      resolved,
      resolvedAt: thread.resolvedAt,
      assignedAdmin: thread.assignedAdmin ? publicPerson(thread.assignedAdmin) : null,
      lastTransfer: lastTransfer
        ? { fromAdmin: lastTransfer.fromAdmin, toAdmin: lastTransfer.toAdmin, createdAt: lastTransfer.createdAt }
        : null,
      otherParticipants: thread.participants.filter((p) => p.userId !== userId).map((p) => publicPerson(p.user)),
      canView,
      // A SUPER_ADMIN can hand an open support conversation to any admin
      // (see reassignThread) unless they're the one handling it — then the
      // ordinary Transfer applies.
      canReassign:
        isAdmin &&
        thread.isSupport &&
        !resolved &&
        thread.assignedAdminId !== userId &&
        (await this.prisma.user.findUnique({ where: { id: userId }, select: { adminLevel: true } }))?.adminLevel ===
          'SUPER_ADMIN',
      // Same rule sendMessage enforces (participant, or any admin on an
      // unclaimed support thread — replying claims it), plus: nobody
      // replies into a resolved thread, and an admin doesn't reply into a
      // support thread another admin is now handling.
      // The customer can rate a resolved support conversation once.
      canRate:
        thread.isSupport &&
        resolved &&
        !isAdmin &&
        isParticipant &&
        // Only once an admin actually replied — there's nothing to rate otherwise.
        !!(await this.prisma.supportChatStat.findFirst({
          where: { threadId, customerId: userId, rating: null, firstResponseAt: { not: null } },
        })),
      // Why a tenant/landlord can't message here right now (payment rules,
      // see landlordTenantBlockReason) — shown in place of the composer.
      lockedReason,
      canReply:
        !resolved &&
        !lockedReason &&
        (isAdmin && thread.isSupport
          ? unclaimedSupport || thread.assignedAdminId === userId
          : isParticipant),
    };
  }

  /// Who has handled a support conversation, oldest first: who first took
  /// it up, every transfer/reassignment (and who made it), and who has it
  /// now. Visible to the admin currently handling it and to SUPER_ADMINs —
  /// the same people who can see into it (a previous handler has lost
  /// access). For conversations claimed before claims were recorded, the
  /// first handler is inferred from the first transfer's "from".
  async getHandlingHistory(threadId: string, userId: string) {
    const thread = await this.prisma.thread.findUnique({
      where: { id: threadId },
      select: {
        isSupport: true,
        assignedAdminId: true,
        assignedAdmin: { select: { id: true, fullName: true } },
        transferLogs: {
          orderBy: { createdAt: 'asc' },
          include: {
            fromAdmin: { select: { id: true, fullName: true } },
            toAdmin: { select: { id: true, fullName: true } },
          },
        },
      },
    });
    if (!thread || !thread.isSupport) throw new NotFoundException('This conversation has no handling history');
    const caller = await this.prisma.user.findUnique({ where: { id: userId }, select: { adminLevel: true } });
    if (thread.assignedAdminId !== userId && caller?.adminLevel !== 'SUPER_ADMIN') {
      throw new ForbiddenException('Only the admin handling this conversation or a super admin can see its history');
    }

    const actorIds = [...new Set(thread.transferLogs.map((l) => l.actorId).filter((id): id is string => !!id))];
    const actors = await this.prisma.user.findMany({
      where: { id: { in: actorIds } },
      select: { id: true, fullName: true },
    });
    const actorById = new Map(actors.map((a) => [a.id, a]));

    const entries = thread.transferLogs.map((log) => ({
      kind: log.kind,
      from: log.fromAdmin,
      to: log.toAdmin,
      by: log.actorId ? (actorById.get(log.actorId) ?? null) : null,
      at: log.createdAt,
    }));
    const firstLog = thread.transferLogs[0];
    const firstHandler = firstLog
      ? firstLog.kind === 'CLAIM' || firstLog.kind === 'AUTO_ASSIGN'
        ? firstLog.toAdmin
        : firstLog.fromAdmin
      : thread.assignedAdmin;
    return { firstHandler, entries, currentAdmin: thread.assignedAdmin };
  }

  /// The customer ends their own support conversation — the same end state
  /// as an admin resolving it (it leaves their inbox, and a later "Contact
  /// Support" starts a fresh conversation), recorded as ended by the
  /// customer. The handling admin (or, if unclaimed, the admins alerted
  /// about it) are told; a notice is posted in the chat.
  async endSupportThreadByCustomer(threadId: string, userId: string): Promise<void> {
    const thread = await this.prisma.thread.findUnique({
      where: { id: threadId },
      select: { isSupport: true, status: true, assignedAdminId: true, participants: { select: { userId: true } } },
    });
    if (!thread?.isSupport || !thread.participants.some((p) => p.userId === userId)) {
      throw new NotFoundException('Support conversation not found');
    }
    if (thread.status === 'RESOLVED') return;
    const endedAt = new Date();
    await this.prisma.$transaction([
      this.prisma.thread.update({ where: { id: threadId }, data: { status: 'RESOLVED', resolvedAt: endedAt } }),
      this.prisma.supportChatStat.updateMany({
        where: { threadId },
        data: { resolvedAt: endedAt, resolvedById: null, closedByCustomer: true },
      }),
    ]);
    await this.postThreadSystemMessage(threadId, 'The customer ended this conversation.');
    // Nobody needs nagging about it any more.
    await this.prisma.notification.updateMany({
      where: { threadId, readAt: null, user: { role: UserRole.ADMIN } },
      data: { readAt: endedAt },
    });
    if (thread.assignedAdminId) {
      await this.notifications.create(
        thread.assignedAdminId,
        NotificationType.SUPPORT_THREAD_RESOLVED,
        'A customer ended their conversation',
        'The customer closed the support conversation you were handling.',
        threadId,
      );
    }
    // Admin queues/inboxes and any admin with it open re-check it.
    this.gateway.broadcastToAdmins('thread:claimed', { threadId });
    this.gateway.broadcastToAdmins('admin:badges-changed', {});
  }

  /// The customer's 1–5 rating of a resolved support conversation (once).
  async rateSupportThread(threadId: string, userId: string, rating: number, comment?: string): Promise<void> {
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId }, select: { isSupport: true, status: true } });
    if (!thread?.isSupport) throw new NotFoundException('Support conversation not found');
    if (thread.status !== 'RESOLVED') throw new BadRequestException('You can rate a conversation once it has been resolved');
    const { count } = await this.prisma.supportChatStat.updateMany({
      where: { threadId, customerId: userId, rating: null, firstResponseAt: { not: null } },
      data: { rating, ratingComment: comment?.trim() || null, ratedAt: new Date() },
    });
    if (count === 0) throw new BadRequestException("This conversation can't be rated (already rated, or nobody replied)");
  }

  async findMessages(threadId: string, userId: string, senderRole?: UserRole, before?: string) {
    await this.assertCanRead(threadId, userId, senderRole);
    const messages = await this.prisma.message.findMany({
      where: { threadId, ...(before ? { createdAt: { lt: new Date(before) } } : {}) },
      orderBy: { createdAt: 'desc' },
      take: MESSAGE_PAGE_SIZE,
      include: { sender: { select: { id: true, fullName: true, firstName: true, role: true } }, replyTo: { select: REPLY_QUOTE_SELECT } },
    });
    const viewerIsAdmin = senderRole === UserRole.ADMIN;
    // Customers only ever see a support admin's first name.
    const nameOf = (sender: { fullName: string | null; firstName: string | null; role: UserRole }) =>
      !viewerIsAdmin && sender.role === UserRole.ADMIN ? adminPublicName(sender) : sender.fullName;
    return messages.reverse().map(({ sender, replyTo, ...message }) => ({
      ...message,
      sender: sender ? { id: sender.id, fullName: nameOf(sender) } : null,
      replyTo: replyQuote(replyTo, nameOf),
    }));
  }

  /// Sends one message into a thread, in order: check it may be sent, save
  /// it, update the support-chat bookkeeping, then notify everyone else.
  /// Returns the message as both sides receive it live.
  async sendMessage(threadId: string, userId: string, senderRole: UserRole, dto: SendMessageDto) {
    const body = await this.assertCanSendMessage(threadId, userId, senderRole, dto);
    const message = await this.saveMessage(threadId, userId, body, dto);
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });
    if (thread?.isSupport) await this.afterSupportMessage(thread, userId, senderRole, message.createdAt);

    // Customers only ever see an admin's first name, in the message itself
    // and in anything it quotes.
    if (senderRole === UserRole.ADMIN && message.sender) message.sender.fullName = adminPublicName(message.sender);
    const { replyTo: quoted, ...sent } = message;
    const outgoing = { ...sent, replyTo: replyQuote(quoted, (s) => (s.role === UserRole.ADMIN ? adminPublicName(s) : s.fullName)) };

    const senderName = message.sender?.fullName ?? 'Someone';
    const preview = messagePreview(body);
    const otherParticipants = await this.prisma.threadParticipant.findMany({
      where: { threadId, userId: { not: userId } },
      select: { userId: true },
    });
    await Promise.all(
      otherParticipants.map((p) =>
        this.notifications.create(p.userId, NotificationType.NEW_MESSAGE, `New message from ${senderName}`, preview, threadId),
      ),
    );
    // A support chat no admin has picked up has nobody to notify above, so
    // every admin is alerted instead.
    if (senderRole !== UserRole.ADMIN && thread?.isSupport && otherParticipants.length === 0) {
      await this.alertAdminsOfWaitingSupportChat(thread, senderName, preview);
      this.gateway.broadcastToAdmins('message:new', { threadId, message: outgoing });
    }
    return outgoing;
  }

  /// Throws if [userId] may not send [dto] into the thread; otherwise
  /// returns the trimmed text. A message needs text, an image, or both.
  private async assertCanSendMessage(threadId: string, userId: string, senderRole: UserRole, dto: SendMessageDto): Promise<string> {
    await this.assertCanWrite(threadId, userId, senderRole);
    // An ended support chat is gone from the customer's inbox, so a reply
    // there would never be seen. The customer starts a new one instead.
    const target = await this.prisma.thread.findUnique({ where: { id: threadId }, select: { isSupport: true, status: true } });
    if (target?.isSupport && target.status === 'RESOLVED') {
      throw new ForbiddenException(
        senderRole === UserRole.ADMIN
          ? 'This conversation has ended.'
          : 'This conversation has ended. Start a new one from Contact Support if you still need help.',
      );
    }
    if (senderRole === UserRole.TENANT || senderRole === UserRole.LANDLORD) {
      const reason = await this.threadBlockReason(threadId, userId);
      if (reason) throw new ForbiddenException(reason);
    }
    const body = dto.body?.trim() ?? '';
    if (!body && !dto.attachmentUrl) {
      throw new BadRequestException('A message needs either text or an image');
    }
    if (dto.attachmentUrl) {
      await this.storage.assertIsOwnImage(dto.attachmentUrl);
    }
    if (dto.replyToId) {
      const original = await this.prisma.message.findFirst({ where: { id: dto.replyToId, threadId }, select: { id: true } });
      if (!original) throw new BadRequestException("The message you're replying to isn't in this conversation");
    }
    return body;
  }

  /// Saves the message and bumps the thread's updatedAt (which orders the
  /// inbox) in one transaction.
  private async saveMessage(threadId: string, userId: string, body: string, dto: SendMessageDto) {
    const [message] = await this.prisma.$transaction([
      this.prisma.message.create({
        data: {
          threadId,
          senderId: userId,
          body,
          type: dto.attachmentUrl ? MessageType.IMAGE : MessageType.TEXT,
          attachmentUrl: dto.attachmentUrl,
          replyToId: dto.replyToId,
        },
        include: { sender: { select: { id: true, fullName: true, firstName: true } }, replyTo: { select: REPLY_QUOTE_SELECT } },
      }),
      this.prisma.thread.update({ where: { id: threadId }, data: { updatedAt: new Date() } }),
    ]);
    return message;
  }

  /// Support-chat bookkeeping after a message is saved. Runs before anyone
  /// is notified, because claiming or assigning the chat adds the admin as
  /// a participant, and participants get the normal new-message alert.
  private async afterSupportMessage(
    thread: { id: string; status: string; assignedAdminId: string | null },
    userId: string,
    senderRole: UserRole,
    sentAt: Date,
  ) {
    const threadId = thread.id;
    // The first admin to reply to an unclaimed chat claims it, the same as
    // opening it from the queue ([claimThread]; [attemptClaim] handles two
    // admins replying at once).
    if (senderRole === UserRole.ADMIN && !thread.assignedAdminId) {
      const claimed = await this.attemptClaim(threadId, userId);
      if (claimed) {
        await this.activityLog.log(ActivityLogType.SUPPORT_THREAD_CLAIMED, { actorId: userId });
        await this.notifications.clearThreadAlertsForOtherAdmins(threadId, userId);
        this.gateway.broadcastToAdmins('thread:claimed', { threadId });
        await this.gateway.evictUnauthorizedFromThread(threadId);
      }
    }

    // Response-time statistics: when the customer first wrote, and when an
    // admin first replied.
    await this.prisma.supportChatStat.updateMany({
      where: senderRole === UserRole.ADMIN ? { threadId, firstResponseAt: null } : { threadId, firstCustomerMessageAt: null },
      data: senderRole === UserRole.ADMIN ? { firstResponseAt: sentAt, firstResponderId: userId } : { firstCustomerMessageAt: sentAt },
    });

    // A customer writing into an open, unassigned chat: give it to an
    // available admin now. If nobody is online and on duty it stays in the
    // shared queue (SupportAlertsService assigns it once someone is), and
    // the customer is told once that a reply may take a while.
    if (senderRole !== UserRole.ADMIN && thread.status === 'OPEN' && !thread.assignedAdminId) {
      const assigned = await this.autoAssign(threadId);
      if (!assigned && !(await this.anyAdminAvailable())) await this.postNobodyAvailableNotice(threadId);
    }
  }

  /// Alerts every admin to a customer message in a support chat nobody has
  /// picked up. One alert per chat: later messages update it quietly
  /// ("Ada (3 messages): …") instead of alerting again. Admins marked
  /// "Away" get it silently (User.adminOnDuty). The 5-minute "still
  /// waiting" reminder is SupportAlertsService's job.
  private async alertAdminsOfWaitingSupportChat(
    thread: { id: string; supportTopic: SupportTopic | null },
    senderName: string,
    preview: string,
  ) {
    const [admins, messageCount] = await Promise.all([
      this.prisma.user.findMany({ where: { role: UserRole.ADMIN }, select: { id: true, adminOnDuty: true } }),
      this.prisma.message.count({ where: { threadId: thread.id } }),
    ]);
    const title = thread.supportTopic ? `New support conversation · ${SUPPORT_TOPIC_LABEL[thread.supportTopic]}` : 'New support conversation';
    const body = messageCount > 1 ? `${senderName} (${messageCount} messages): ${preview}` : `${senderName}: ${preview}`;
    await Promise.all(
      admins.map((admin) =>
        this.notifications.upsertThreadAlert(admin.id, NotificationType.NEW_MESSAGE, thread.id, title, body, !admin.adminOnDuty),
      ),
    );
  }

  /// Posts an automatic SYSTEM message (no sender) into a thread and pushes
  /// it live to everyone in it — used for notices both sides should see.
  async postThreadSystemMessage(threadId: string, body: string) {
    const [message] = await this.prisma.$transaction([
      this.prisma.message.create({
        data: { threadId, senderId: null, body, type: MessageType.SYSTEM },
        include: { sender: { select: { id: true, fullName: true } } },
      }),
      this.prisma.thread.update({ where: { id: threadId }, data: { updatedAt: new Date() } }),
    ]);
    this.gateway.broadcastMessage(await this.participantIds(threadId), '', threadId, message);
    return message;
  }

  /// Tells the customer (and the admins) in the chat itself that it changed
  /// hands — by first name only, so an admin's full name isn't shared.
  private async postHandoffNotice(threadId: string, toAdminId: string): Promise<void> {
    const admin = await this.prisma.user.findUnique({ where: { id: toAdminId }, select: { fullName: true, firstName: true } });
    const firstName = adminPublicName(admin);
    const who = firstName ? `${firstName} from HomeServant Support` : 'another member of HomeServant Support';
    try {
      await this.postThreadSystemMessage(threadId, `This conversation has been transferred to ${who}.`);
    } catch {
      // The hand-off itself already happened — a missing notice isn't worth failing it.
    }
  }

  /// Picks the admin to hand a new support conversation to: on duty, not
  /// deactivated and online right now; fewest open support chats first,
  /// then whoever was assigned one longest ago (so equal loads rotate).
  /// Returns the admin's id, or null if nobody qualifies — or if auto-
  /// assignment is switched off with SUPPORT_AUTO_ASSIGN=false — in which
  /// case the conversation waits in the shared queue as before.
  async pickAssignee(): Promise<string | null> {
    if (process.env.SUPPORT_AUTO_ASSIGN === 'false') return null;
    const admins = await this.prisma.user.findMany({
      where: { role: UserRole.ADMIN, adminOnDuty: true, deactivatedAt: null },
      select: { id: true },
    });
    const candidates = admins.map((a) => a.id).filter((id) => this.presence.isOnline(id));
    if (candidates.length === 0) return null;
    const [loads, lastAssigned] = await Promise.all([
      this.prisma.thread.groupBy({
        by: ['assignedAdminId'],
        where: { isSupport: true, status: 'OPEN', assignedAdminId: { in: candidates } },
        _count: true,
      }),
      this.prisma.threadTransferLog.groupBy({
        by: ['toAdminId'],
        where: { toAdminId: { in: candidates } },
        _max: { createdAt: true },
      }),
    ]);
    const load = new Map(loads.map((l) => [l.assignedAdminId, l._count]));
    const last = new Map(lastAssigned.map((l) => [l.toAdminId, l._max.createdAt?.getTime() ?? 0]));
    candidates.sort((a, b) => (load.get(a) ?? 0) - (load.get(b) ?? 0) || (last.get(a) ?? 0) - (last.get(b) ?? 0));
    return candidates[0];
  }

  /// Whether any admin is on duty and online right now.
  async anyAdminAvailable(): Promise<boolean> {
    const admins = await this.prisma.user.findMany({
      where: { role: UserRole.ADMIN, adminOnDuty: true, deactivatedAt: null },
      select: { id: true },
    });
    return admins.some((a) => this.presence.isOnline(a.id));
  }

  /// Once per conversation: tells a customer who wrote in while nobody was
  /// around that they're in the queue and how they'll hear back (the
  /// in-app/push notification on reply, and the unread-message email).
  private async postNobodyAvailableNotice(threadId: string): Promise<void> {
    const already = await this.prisma.message.findFirst({
      where: { threadId, type: MessageType.SYSTEM, body: { startsWith: NOBODY_AVAILABLE_PREFIX } },
      select: { id: true },
    });
    if (already) return;
    await this.postThreadSystemMessage(
      threadId,
      `${NOBODY_AVAILABLE_PREFIX} No one from our support team is available right now, but your conversation is in the queue ` +
        "and we'll reply as soon as someone is back. You'll get a notification, and an email if you're away, when we do.",
    );
  }

  /// Hands waiting (unclaimed) support conversations to available admins,
  /// most urgent and oldest first, until nobody suitable is left. Run every
  /// minute by SupportAlertsService and straight away when an admin goes
  /// on duty — so a chat that arrived while everyone was away is picked up
  /// the moment someone is back, not only when the customer writes again.
  async assignWaitingQueue(): Promise<number> {
    const waiting = await this.prisma.thread.findMany({
      where: { isSupport: true, status: 'OPEN', assignedAdminId: null, messages: { some: {} } },
      orderBy: [{ priority: 'desc' }, { createdAt: 'asc' }],
      select: { id: true, supportTopic: true },
      take: 25,
    });
    let assigned = 0;
    for (const thread of waiting) {
      const adminId = await this.autoAssign(thread.id);
      if (adminId) {
        assigned++;
        const about = thread.supportTopic ? ` about ${SUPPORT_TOPIC_LABEL[thread.supportTopic]}` : '';
        await this.notifications.create(
          adminId,
          NotificationType.NEW_MESSAGE,
          'Auto assigned to you by system admin',
          `A customer has been waiting in the support queue${about} — the system assigned the conversation to you.`,
          thread.id,
        );
      } else if (!(await this.pickAssignee())) {
        break;
      }
    }
    return assigned;
  }

  private async autoAssign(threadId: string): Promise<string | null> {
    const adminId = await this.pickAssignee();
    if (!adminId) return null;
    // Race-safe: loses quietly if an admin claimed it a moment earlier.
    if (!(await this.attemptClaim(threadId, adminId, 'AUTO_ASSIGN'))) return null;
    await this.notifications.clearThreadAlertsForOtherAdmins(threadId, adminId);
    this.gateway.broadcastToAdmins('thread:claimed', { threadId });
    return adminId;
  }

  /// Posts an automatic SYSTEM message (no sender) into the chat between a
  /// tenant and landlord about [propertyId] — e.g. when a booking is
  /// refunded or rejected and messaging closes (see
  /// landlordTenantBlockReason). Both sides see it live. With
  /// [createIfMissing], a thread is started for it when none exists yet
  /// (so a rejected tenant finds the notice in Messages); otherwise it's
  /// only added to an existing conversation. Returns the thread id, if any.
  async postBookingSystemMessage(opts: {
    tenantId: string;
    landlordId: string;
    propertyId: string;
    body: string;
    createIfMissing: boolean;
  }): Promise<string | null> {
    const { tenantId, landlordId, propertyId, body, createIfMissing } = opts;
    let thread = await this.prisma.thread.findFirst({
      where: {
        propertyId,
        orderId: null,
        isSupport: false,
        AND: [{ participants: { some: { userId: tenantId } } }, { participants: { some: { userId: landlordId } } }],
      },
      select: { id: true },
    });
    if (!thread) {
      if (!createIfMissing) return null;
      thread = await this.prisma.thread.create({
        data: { propertyId, participants: { create: [{ userId: tenantId }, { userId: landlordId }] } },
        select: { id: true },
      });
    }
    await this.postThreadSystemMessage(thread.id, body);
    return thread.id;
  }

  async markRead(threadId: string, userId: string, senderRole?: UserRole): Promise<void> {
    await this.assertCanRead(threadId, userId, senderRole);
    // Opening a conversation also marks the caller's notifications about it
    // read, so the bell count drops with the chat's.
    await this.prisma.notification.updateMany({
      where: { userId, threadId, readAt: null },
      data: { readAt: new Date() },
    });
    // A read-only viewer (a SUPER_ADMIN looking into another admin's
    // conversation) must not mark messages read on that admin's behalf —
    // it would silently clear their unread badge.
    if (!(await this.canWrite(threadId, userId, senderRole))) return;
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

  /// Who may *reply* (send, mark read, resolve): a real [ThreadParticipant],
  /// or any admin on a support thread nobody has claimed yet (the shared
  /// Support Queue — [sendMessage]'s auto-claim is what then makes them a
  /// participant). Every other thread, and every other role, requires real
  /// participancy.
  private async canWrite(threadId: string, userId: string, senderRole?: UserRole): Promise<boolean> {
    const membership = await this.prisma.threadParticipant.findUnique({
      where: { threadId_userId: { threadId, userId } },
    });
    if (membership) return true;
    if (senderRole !== 'ADMIN') return false;
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });
    return !!thread && thread.isSupport && !thread.assignedAdminId;
  }

  /// Tenant/landlord messaging is tied to payment, so the two do business
  /// through the platform. Returns why [senderId] can't message the other
  /// side right now, or null if they can:
  ///
  /// - a paid booking (PAID through MOVED_IN) opens it both ways;
  /// - otherwise, a refunded booking (the tenant's own refund, or the
  ///   landlord rejecting a paid booking) closes it both ways until the
  ///   tenant pays again;
  /// - otherwise (nothing paid yet) a landlord may reach out, and the
  ///   tenant may only answer a thread the landlord has already written in.
  ///
  /// Bookings are those on [propertyId], or on any of the landlord's
  /// properties for a thread not tied to a listing.
  private async landlordTenantBlockReason(
    { tenantId, landlordId }: LandlordTenantPair,
    senderId: string,
    propertyId: string | null,
    threadId?: string,
  ): Promise<string | null> {
    const bookings = await this.prisma.booking.findMany({
      where: { tenantId, property: propertyId ? { id: propertyId, landlordId } : { landlordId } },
      select: { status: true, payments: { where: { status: PaymentStatus.REFUNDED }, select: { id: true }, take: 1 } },
    });
    if (bookings.some((b) => PAID_BOOKING_STATUSES.includes(b.status))) return null;
    const refunded = bookings.some(
      (b) => b.status === BookingStatus.REFUNDED || (b.status === BookingStatus.DECLINED && b.payments.length > 0),
    );
    if (refunded) return REFUNDED_MESSAGE;
    if (senderId === landlordId) return null;
    if (threadId) {
      const landlordWrote = await this.prisma.message.findFirst({
        where: { threadId, senderId: landlordId },
        select: { id: true },
      });
      if (landlordWrote) return null;
    }
    return PAYMENT_REQUIRED_MESSAGE;
  }

  /// [landlordTenantBlockReason] for an existing thread — null for support
  /// and marketplace order threads, and anything that isn't exactly one
  /// tenant and one landlord.
  private async threadBlockReason(threadId: string, senderId: string): Promise<string | null> {
    const thread = await this.prisma.thread.findUnique({
      where: { id: threadId },
      select: {
        isSupport: true,
        orderId: true,
        propertyId: true,
        participants: { select: { user: { select: { id: true, role: true } } } },
      },
    });
    if (!thread || thread.isSupport || thread.orderId) return null;
    const pair = this.asLandlordTenantPair(thread.participants.map((p) => p.user));
    if (!pair) return null;
    return this.landlordTenantBlockReason(pair, senderId, thread.propertyId, threadId);
  }

  private asLandlordTenantPair(people: { id: string; role?: UserRole | null }[]): LandlordTenantPair | null {
    if (people.length !== 2) return null;
    const tenant = people.find((p) => p.role === UserRole.TENANT);
    const landlord = people.find((p) => p.role === UserRole.LANDLORD);
    return tenant && landlord ? { tenantId: tenant.id, landlordId: landlord.id } : null;
  }

  /// For the admin support tools (notes, triage, customer context): the
  /// thread must be a support thread this admin can see into — they're
  /// handling it, it's unclaimed, or they're a SUPER_ADMIN. [write] also
  /// requires being able to act on it (a super admin always may).
  async assertAdminCanUseSupportThread(threadId: string, adminId: string, write = false) {
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });
    if (!thread || !thread.isSupport) throw new NotFoundException('Support conversation not found');
    if (await this.canWrite(threadId, adminId, UserRole.ADMIN)) return thread;
    const admin = await this.prisma.user.findUnique({ where: { id: adminId }, select: { adminLevel: true } });
    if (admin?.adminLevel === 'SUPER_ADMIN') return thread;
    if (!write && (await adminCanAccessSupportThread(this.prisma, thread, adminId))) return thread;
    throw new ForbiddenException('This conversation is being handled by another admin');
  }

  private async assertCanWrite(threadId: string, userId: string, senderRole?: UserRole): Promise<void> {
    if (!(await this.canWrite(threadId, userId, senderRole))) {
      throw new ForbiddenException('Not a participant of this thread');
    }
  }

  /// Who may *read*: everyone who can write, plus a SUPER_ADMIN on a
  /// support thread another admin is handling — read-only oversight (see
  /// adminCanAccessSupportThread). No other admin can see into a support
  /// thread someone else is handling.
  private async assertCanRead(threadId: string, userId: string, senderRole?: UserRole): Promise<void> {
    if (await this.canWrite(threadId, userId, senderRole)) return;
    if (senderRole === 'ADMIN') {
      const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });
      if (thread && (await adminCanAccessSupportThread(this.prisma, thread, userId))) return;
    }
    throw new ForbiddenException('Not a participant of this thread');
  }

  /// SUPER_ADMIN-only (enforced by the controller's guards): moves an open
  /// support thread to [toAdminId] regardless of who's handling it — for a
  /// conversation stuck with an admin who's away, or one nobody has picked
  /// up. Unlike [transferThread], the caller doesn't need to be in the
  /// thread (a super admin only ever reads other admins' chats). The
  /// previous handler's participant row is handed to [toAdminId] (so they
  /// lose access, same as after a normal transfer), the hand-off is
  /// recorded in the transfer chain, and both the new and previous admin
  /// are notified.
  async reassignThread(threadId: string, superAdminId: string, toAdminId: string): Promise<void> {
    const thread = await this.prisma.thread.findUnique({ where: { id: threadId } });
    if (!thread || !thread.isSupport) throw new NotFoundException('Support thread not found');
    if (thread.status === 'RESOLVED') throw new ForbiddenException("Can't reassign a resolved conversation");
    if (thread.assignedAdminId === toAdminId) throw new ForbiddenException('That admin is already handling this conversation');

    const toAdmin = await this.prisma.user.findUnique({ where: { id: toAdminId } });
    if (!toAdmin || toAdmin.role !== 'ADMIN') throw new NotFoundException('Admin not found');

    const previousAdminId = thread.assignedAdminId;
    const previousMembership = previousAdminId
      ? await this.prisma.threadParticipant.findUnique({ where: { threadId_userId: { threadId, userId: previousAdminId } } })
      : null;
    const newAdminAlreadyIn = await this.prisma.threadParticipant.findUnique({
      where: { threadId_userId: { threadId, userId: toAdminId } },
    });

    await this.prisma.$transaction([
      // Hand the previous handler's seat over (keeps their messages'
      // history/read state intact, same as transferThread), or add the new
      // admin fresh if nobody held one.
      ...(previousMembership && !newAdminAlreadyIn
        ? [this.prisma.threadParticipant.update({ where: { id: previousMembership.id }, data: { userId: toAdminId } })]
        : previousMembership
          ? [this.prisma.threadParticipant.delete({ where: { id: previousMembership.id } })]
          : []),
      ...(!previousMembership && !newAdminAlreadyIn
        ? [this.prisma.threadParticipant.create({ data: { threadId, userId: toAdminId } })]
        : []),
      this.prisma.thread.update({ where: { id: threadId }, data: { assignedAdminId: toAdminId } }),
      this.prisma.threadTransferLog.create({
        data: { threadId, fromAdminId: previousAdminId, toAdminId, actorId: superAdminId, kind: 'REASSIGN' },
      }),
      this.prisma.supportChatStat.updateMany({
        where: { threadId },
        data: { currentAdminId: toAdminId, transferCount: { increment: 1 } },
      }),
    ]);
    await this.activityLog.log(ActivityLogType.SUPPORT_THREAD_TRANSFERRED, { actorId: superAdminId, targetId: toAdminId });
    await this.notifications.clearThreadAlertsForOtherAdmins(threadId, toAdminId);
    this.gateway.broadcastToAdmins('thread:claimed', { threadId });
    await this.gateway.evictUnauthorizedFromThread(threadId);
    await this.postHandoffNotice(threadId, toAdminId);

    await this.notifications.create(
      toAdminId,
      NotificationType.THREAD_TRANSFERRED,
      'A conversation was assigned to you',
      'A super admin assigned a support conversation to you.',
      threadId,
    );
    await this.mail.send(
      toAdmin.email,
      'A HomeServant conversation was assigned to you',
      '<p>A super admin assigned a support conversation to you — open Messages in the admin console to continue it.</p>',
      'A super admin assigned a support conversation to you — open Messages in the admin console to continue it.',
    );
    if (previousAdminId && previousAdminId !== superAdminId) {
      await this.notifications.create(
        previousAdminId,
        NotificationType.THREAD_TRANSFERRED,
        'A conversation was reassigned',
        `A super admin reassigned a support conversation you were handling to ${toAdmin.fullName ?? 'another admin'}.`,
        threadId,
      );
    }
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
      this.prisma.threadTransferLog.create({
        data: { threadId, fromAdminId, toAdminId, actorId: fromAdminId, kind: 'TRANSFER' },
      }),
      this.prisma.supportChatStat.updateMany({
        where: { threadId },
        data: { currentAdminId: toAdminId, transferCount: { increment: 1 } },
      }),
    ]);
    await this.activityLog.log(ActivityLogType.SUPPORT_THREAD_TRANSFERRED, { actorId: fromAdminId, targetId: toAdminId });
    // Same "this thread changed hands" signal a claim sends — lets any
    // admin with it open (including the one who just handed it off)
    // re-check their access and go read-only.
    await this.notifications.clearThreadAlertsForOtherAdmins(threadId, toAdminId);
    this.gateway.broadcastToAdmins('thread:claimed', { threadId });
    await this.gateway.evictUnauthorizedFromThread(threadId);
    await this.postHandoffNotice(threadId, toAdminId);

    await this.notifications.create(
      toAdminId,
      NotificationType.THREAD_TRANSFERRED,
      'A conversation was transferred to you',
      'Another admin handed off a console conversation to you.',
      threadId,
    );
    await this.mail.send(
      toAdmin.email,
      'A HomeServant conversation was transferred to you',
      '<p>Another admin handed off a console conversation to you — open Messages in the admin console to continue it.</p>',
      'Another admin handed off a console conversation to you — open Messages in the admin console to continue it.',
    );
  }
}

/// What a reply shows of the message it quotes.
/// Notification preview text: the message, cut to 140 characters, or
/// "📷 Photo" for an image sent without a caption.
function messagePreview(body: string): string {
  const text = body || '📷 Photo';
  return text.length > 140 ? `${text.slice(0, 140)}…` : text;
}

const REPLY_QUOTE_SELECT = {
  id: true,
  body: true,
  type: true,
  attachmentUrl: true,
  sender: { select: { id: true, fullName: true, firstName: true, role: true } },
} as const;

type QuotedSender = { id: string; fullName: string | null; firstName: string | null; role: UserRole };

/// The short quote sent with a reply: who wrote the original and its text
/// (a photo shows as "Photo"). Null when it isn't a reply, or the original
/// was deleted.
function replyQuote(
  original: { id: string; body: string; type: MessageType; attachmentUrl: string | null; sender: QuotedSender | null } | null,
  nameOf: (sender: QuotedSender) => string | null,
) {
  if (!original) return null;
  return {
    id: original.id,
    body: original.body,
    isImage: original.type === MessageType.IMAGE || (!!original.attachmentUrl && !original.body),
    senderId: original.sender?.id ?? null,
    senderName: original.sender ? nameOf(original.sender) : null,
  };
}
