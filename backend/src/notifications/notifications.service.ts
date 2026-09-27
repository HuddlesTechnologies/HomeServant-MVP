import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { NotificationType } from '@prisma/client';
import { ChatGateway } from '../chat/chat.gateway';
import { PrismaService } from '../prisma/prisma.service';

/// The single choke-point every notification (chat, admin, payments,
/// reports, …) already passes through — also emitting a `notification:new`
/// socket event here, over ChatGateway's existing connection, is what makes
/// every one of those instantly show up as an in-app banner without every
/// call site having to know about realtime delivery itself.
@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly chatGateway: ChatGateway,
  ) {}

  /// [threadId] links a chat-related notification to its thread (see
  /// Notification.threadId). [silent] asks the client not to play a sound
  /// or pop a banner for it (the row still lands in the list) — used for an
  /// "Away" admin's queue alerts; see ChatService.sendMessage.
  async create(userId: string, type: NotificationType, title: string, body: string, threadId?: string, silent = false) {
    const notification = await this.prisma.notification.create({ data: { userId, type, title, body, threadId } });
    this.emit(notification, silent);
    return notification;
  }

  /// One alert per thread instead of one per message: if [userId] still
  /// has an unread [type] notification for [threadId], it's updated in
  /// place (new text, moved to the top) and pushed as a silent update —
  /// no second sound or banner. Otherwise a new one is created, audible
  /// unless [silent].
  async upsertThreadAlert(
    userId: string,
    type: NotificationType,
    threadId: string,
    title: string,
    body: string,
    silent = false,
  ) {
    const existing = await this.prisma.notification.findFirst({
      where: { userId, type, threadId, readAt: null },
      orderBy: { createdAt: 'desc' },
    });
    if (!existing) return this.create(userId, type, title, body, threadId, silent);
    const updated = await this.prisma.notification.update({
      where: { id: existing.id },
      data: { title, body, createdAt: new Date() },
    });
    this.emit(updated, true);
    return updated;
  }

  /// Marks every admin's unread [NotificationType.NEW_MESSAGE] alerts for
  /// [threadId] read, except [exceptUserId]'s — called the moment a support
  /// thread is claimed or reassigned, so the "new support conversation"
  /// alert stops nagging everyone who isn't handling it. Clients learn
  /// about it from the `thread:claimed` broadcast and refetch.
  async clearThreadAlertsForOtherAdmins(threadId: string, exceptUserId: string): Promise<void> {
    await this.prisma.notification.updateMany({
      where: {
        threadId,
        type: NotificationType.NEW_MESSAGE,
        readAt: null,
        userId: { not: exceptUserId },
        user: { role: 'ADMIN' },
      },
      data: { readAt: new Date() },
    });
  }

  // Same per-row shape GET /notifications already returns — the client's
  // AppNotification.fromApi parses this socket payload identically, plus
  // the transient [silent] flag.
  private emit(
    notification: { id: string; userId: string; type: NotificationType; title: string; body: string; threadId: string | null; createdAt: Date },
    silent: boolean,
  ): void {
    this.chatGateway.emitToUser(notification.userId, 'notification:new', {
      id: notification.id,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      threadId: notification.threadId,
      createdAt: notification.createdAt,
      silent,
    });
  }

  findMine(userId: string) {
    return this.prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }

  unreadCount(userId: string) {
    return this.prisma.notification.count({ where: { userId, readAt: null } });
  }

  async markRead(userId: string, id: string) {
    const notification = await this.prisma.notification.findUnique({ where: { id } });
    if (!notification) throw new NotFoundException('Notification not found');
    if (notification.userId !== userId) throw new ForbiddenException('Not your notification');
    if (notification.readAt) return notification;
    return this.prisma.notification.update({ where: { id }, data: { readAt: new Date() } });
  }

  async markAllRead(userId: string): Promise<void> {
    await this.prisma.notification.updateMany({ where: { userId, readAt: null }, data: { readAt: new Date() } });
  }
}
