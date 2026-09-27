import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { SupportPriority, SupportTopic, UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChatGateway } from './chat.gateway';
import { ChatService } from './chat.service';
import { PresenceService } from './presence.service';

/// The admin console's tools around a support conversation: internal
/// notes (never shown to the customer), topic/priority triage, the
/// customer's context (bookings, payments, reports, past chats), shared
/// saved replies, and the list of admins a chat can be handed to.
@Injectable()
export class SupportToolsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly chat: ChatService,
    private readonly gateway: ChatGateway,
    private readonly presence: PresenceService,
  ) {}

  // --- Internal notes ------------------------------------------------------

  async listNotes(threadId: string, adminId: string) {
    await this.chat.assertAdminCanUseSupportThread(threadId, adminId);
    return this.prisma.supportNote.findMany({
      where: { threadId },
      orderBy: { createdAt: 'asc' },
      include: { author: { select: { id: true, fullName: true, email: true } } },
    });
  }

  async addNote(threadId: string, adminId: string, body: string) {
    await this.chat.assertAdminCanUseSupportThread(threadId, adminId);
    return this.prisma.supportNote.create({
      data: { threadId, authorId: adminId, body: body.trim() },
      include: { author: { select: { id: true, fullName: true, email: true } } },
    });
  }

  // --- Triage ----------------------------------------------------------------

  async triage(threadId: string, adminId: string, topic?: SupportTopic, priority?: SupportPriority) {
    await this.chat.assertAdminCanUseSupportThread(threadId, adminId, true);
    const updated = await this.prisma.thread.update({
      where: { id: threadId },
      data: { ...(topic ? { supportTopic: topic } : {}), ...(priority ? { priority } : {}) },
      select: { id: true, supportTopic: true, priority: true },
    });
    await this.prisma.supportChatStat.updateMany({
      where: { threadId },
      data: { ...(topic ? { topic } : {}), ...(priority ? { priority } : {}) },
    });
    // Queues/inboxes re-sort by priority — let every open console refetch.
    this.gateway.broadcastToAdmins('admin:badges-changed', {});
    return updated;
  }

  // --- Customer context --------------------------------------------------------

  /// Everything an admin needs about the person on the other end, beside
  /// the conversation: who they are, their recent bookings (as a tenant, or
  /// on their listings as a landlord), recent payments either way, reports,
  /// and their other support conversations.
  async customerContext(threadId: string, adminId: string) {
    await this.chat.assertAdminCanUseSupportThread(threadId, adminId);
    const participants = await this.prisma.threadParticipant.findMany({
      where: { threadId },
      select: { user: { select: { id: true, role: true } } },
    });
    const customerId = participants.find((p) => p.user.role !== UserRole.ADMIN)?.user.id;
    if (!customerId) throw new NotFoundException('No customer on this conversation');

    const [user, tenantBookings, landlordBookings, listings, payments, reportsFiled, openReportsOnListings, pastChats] =
      await Promise.all([
        this.prisma.user.findUnique({
          where: { id: customerId },
          select: {
            id: true,
            fullName: true,
            email: true,
            phoneNumber: true,
            role: true,
            createdAt: true,
            deactivatedAt: true,
            emailVerifiedAt: true,
            vendorProfile: { select: { businessName: true, status: true } },
          },
        }),
        this.prisma.booking.findMany({
          where: { tenantId: customerId },
          orderBy: { createdAt: 'desc' },
          take: 5,
          select: { id: true, status: true, createdAt: true, property: { select: { title: true } } },
        }),
        this.prisma.booking.findMany({
          where: { property: { landlordId: customerId } },
          orderBy: { createdAt: 'desc' },
          take: 5,
          select: {
            id: true,
            status: true,
            createdAt: true,
            property: { select: { title: true } },
            tenant: { select: { fullName: true } },
          },
        }),
        this.prisma.property.groupBy({ by: ['isOccupied'], where: { landlordId: customerId }, _count: true }),
        this.prisma.payment.findMany({
          where: { OR: [{ payerId: customerId }, { recipientUserId: customerId }] },
          orderBy: { createdAt: 'desc' },
          take: 5,
          select: { id: true, amount: true, status: true, purpose: true, createdAt: true, payerId: true },
        }),
        this.prisma.report.count({ where: { reporterId: customerId } }),
        this.prisma.report.count({
          where: { status: { in: ['OPEN', 'IN_PROGRESS'] }, property: { landlordId: customerId } },
        }),
        this.prisma.thread.findMany({
          where: { isSupport: true, id: { not: threadId }, participants: { some: { userId: customerId } } },
          orderBy: { createdAt: 'desc' },
          take: 5,
          select: { id: true, status: true, supportTopic: true, createdAt: true, resolvedAt: true },
        }),
      ]);
    if (!user) throw new NotFoundException('Customer not found');

    const listingCount = listings.reduce((sum, g) => sum + g._count, 0);
    const occupiedCount = listings.find((g) => g.isOccupied)?._count ?? 0;
    return {
      user,
      tenantBookings: tenantBookings.map((b) => ({
        id: b.id,
        status: b.status,
        createdAt: b.createdAt,
        propertyTitle: b.property.title,
      })),
      landlordBookings: landlordBookings.map((b) => ({
        id: b.id,
        status: b.status,
        createdAt: b.createdAt,
        propertyTitle: b.property.title,
        tenantName: b.tenant.fullName,
      })),
      listings: { total: listingCount, occupied: occupiedCount },
      payments: payments.map(({ payerId, ...p }) => ({ ...p, direction: payerId === customerId ? 'PAID' : 'RECEIVED' })),
      reports: { filed: reportsFiled, openOnTheirListings: openReportsOnListings },
      pastChats,
    };
  }

  // --- Saved replies -----------------------------------------------------------

  listSavedReplies() {
    return this.prisma.savedReply.findMany({
      orderBy: { title: 'asc' },
      include: { createdBy: { select: { id: true, fullName: true } } },
    });
  }

  createSavedReply(adminId: string, title: string, body: string) {
    return this.prisma.savedReply.create({ data: { title: title.trim(), body: body.trim(), createdById: adminId } });
  }

  async updateSavedReply(id: string, adminId: string, title: string, body: string) {
    await this.assertCanEditSavedReply(id, adminId);
    return this.prisma.savedReply.update({ where: { id }, data: { title: title.trim(), body: body.trim() } });
  }

  async deleteSavedReply(id: string, adminId: string): Promise<void> {
    await this.assertCanEditSavedReply(id, adminId);
    await this.prisma.savedReply.delete({ where: { id } });
  }

  /// The author can edit/delete their own; moderators and super admins can
  /// edit/delete any (e.g. to fix an outdated answer).
  private async assertCanEditSavedReply(id: string, adminId: string): Promise<void> {
    const reply = await this.prisma.savedReply.findUnique({ where: { id }, select: { createdById: true } });
    if (!reply) throw new NotFoundException('Saved reply not found');
    if (reply.createdById === adminId) return;
    const admin = await this.prisma.user.findUnique({ where: { id: adminId }, select: { adminLevel: true } });
    if (admin?.adminLevel === 'MODERATOR' || admin?.adminLevel === 'SUPER_ADMIN') return;
    throw new ForbiddenException('Only the author, a moderator or a super admin can change this saved reply');
  }

  // --- Hand-off targets -----------------------------------------------------------

  /// Every active admin a chat can be handed to, with what helps pick the
  /// right one: permission level, whether they're on duty and online, and
  /// how many open support chats they're already handling. Open to any
  /// admin — transferring used to load `/admin/admins`, which is
  /// super-admin-only, so other admins couldn't transfer at all.
  async transferTargets() {
    const [admins, loads] = await Promise.all([
      this.prisma.user.findMany({
        where: { role: UserRole.ADMIN, deactivatedAt: null },
        select: { id: true, fullName: true, email: true, adminLevel: true, adminOnDuty: true },
        orderBy: { fullName: 'asc' },
      }),
      this.prisma.thread.groupBy({
        by: ['assignedAdminId'],
        where: { isSupport: true, status: 'OPEN', assignedAdminId: { not: null } },
        _count: true,
      }),
    ]);
    const loadByAdmin = new Map(loads.map((l) => [l.assignedAdminId, l._count]));
    return admins.map((a) => ({
      ...a,
      isOnline: this.presence.isOnline(a.id),
      openChats: loadByAdmin.get(a.id) ?? 0,
    }));
  }
}

