import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateThreadDto } from './dto/create-thread.dto';
import { SendMessageDto } from './dto/send-message.dto';

const MESSAGE_PAGE_SIZE = 50;

@Injectable()
export class ChatService {
  constructor(private readonly prisma: PrismaService) {}

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

  async findForUser(userId: string) {
    const threads = await this.prisma.thread.findMany({
      where: { participants: { some: { userId } } },
      include: {
        participants: { include: { user: { select: { id: true, fullName: true, profilePhotoUrl: true } } } },
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
      otherParticipants: thread.participants.filter((p) => p.userId !== userId).map((p) => p.user),
      lastMessage: thread.messages[0] ?? null,
      unreadCount: unreadByThread.get(thread.id) ?? 0,
      updatedAt: thread.updatedAt,
    }));
  }

  async findMessages(threadId: string, userId: string, before?: string) {
    await this.assertParticipant(threadId, userId);
    const messages = await this.prisma.message.findMany({
      where: { threadId, ...(before ? { createdAt: { lt: new Date(before) } } : {}) },
      orderBy: { createdAt: 'desc' },
      take: MESSAGE_PAGE_SIZE,
      include: { sender: { select: { id: true, fullName: true } } },
    });
    return messages.reverse();
  }

  async sendMessage(threadId: string, userId: string, dto: SendMessageDto) {
    await this.assertParticipant(threadId, userId);
    const [message] = await this.prisma.$transaction([
      this.prisma.message.create({
        data: { threadId, senderId: userId, body: dto.body },
        include: { sender: { select: { id: true, fullName: true } } },
      }),
      this.prisma.thread.update({ where: { id: threadId }, data: { updatedAt: new Date() } }),
    ]);
    return message;
  }

  async markRead(threadId: string, userId: string): Promise<void> {
    await this.assertParticipant(threadId, userId);
    await this.prisma.message.updateMany({
      where: { threadId, senderId: { not: userId }, readAt: null },
      data: { readAt: new Date() },
    });
  }

  private async assertParticipant(threadId: string, userId: string): Promise<void> {
    const membership = await this.prisma.threadParticipant.findUnique({
      where: { threadId_userId: { threadId, userId } },
    });
    if (!membership) throw new ForbiddenException('Not a participant of this thread');
  }
}
