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

  async create(userId: string, type: NotificationType, title: string, body: string) {
    const notification = await this.prisma.notification.create({ data: { userId, type, title, body } });
    // Same per-row shape GET /notifications already returns — the client's
    // AppNotification.fromApi parses this socket payload identically.
    this.chatGateway.emitToUser(userId, 'notification:new', {
      id: notification.id,
      type: notification.type,
      title: notification.title,
      body: notification.body,
      createdAt: notification.createdAt,
    });
    return notification;
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
