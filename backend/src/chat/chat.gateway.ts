import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtPayload } from '../auth/strategies/jwt.strategy';
import { PrismaService } from '../prisma/prisma.service';
import { PresenceService } from './presence.service';
import { adminCanAccessSupportThread } from './support-access';

/// Same allow-list `main.ts` builds from CORS_ORIGINS for the REST API —
/// duplicated here because `@WebSocketGateway`'s options are evaluated at
/// class-decoration time, before Nest's DI (and ConfigService) exist, so
/// this can't just inject ConfigService the way a normal provider would.
const socketCorsOrigins = (process.env.CORS_ORIGINS ?? 'http://localhost:8765').split(',').map((o) => o.trim());

/// Real-time delivery for chat — previously a thread's messages only ever
/// loaded once, when the screen opened, with no polling and no push, so a
/// message sent by the other party while you were already looking at the
/// thread just never appeared until you left and reopened it.
///
/// Auth happens once, at the socket handshake (the same access token the
/// REST API uses, passed as `auth: { token }` from the client) rather than
/// per-event — there's no separate "login" message. Every connected
/// socket joins a room named after its own user id; [broadcastMessage]
/// (called by ChatController right after ChatService persists a message)
/// emits into the *other* participants' rooms, not the sender's own, so a
/// message never bounces back to whoever just sent it.
@WebSocketGateway({ cors: { origin: socketCorsOrigins, credentials: true } })
export class ChatGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger('ChatGateway');

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly presence: PresenceService,
    private readonly prisma: PrismaService,
  ) {
    prisma.onListingsChanged(() => this.scheduleListingsBroadcast());
  }

  private listingsTimer: NodeJS.Timeout | null = null;

  /// Tells every connected app that browse results may have changed (a
  /// listing edited, or a rental paid for / moved into / relisted), so a
  /// tenant's home screen drops a property someone else just rented
  /// without a reload. Debounced: one write often comes with several
  /// (and within a transaction, lands before the commit), so this waits a
  /// moment and sends a single event.
  private scheduleListingsBroadcast(): void {
    if (this.listingsTimer) return;
    this.listingsTimer = setTimeout(() => {
      this.listingsTimer = null;
      this.server?.emit('listings:changed');
    }, 1500);
  }

  async handleConnection(client: Socket): Promise<void> {
    const token = client.handshake.auth?.token as string | undefined;
    if (!token) {
      client.disconnect();
      return;
    }
    try {
      const payload = await this.jwt.verifyAsync<JwtPayload>(token, { secret: this.config.getOrThrow('JWT_ACCESS_SECRET') });
      client.data.userId = payload.sub;
      client.data.role = payload.role;
      await client.join(this.userRoom(payload.sub));
      // Lets [broadcastToAdmins] reach every connected admin at once — used
      // for events with no single-user room to target yet, like a brand-new
      // unclaimed "Contact Support" message (see ChatService.sendMessage).
      if (payload.role === 'ADMIN') {
        await client.join(this.adminRoom());
      }
      this.presence.markOnline(payload.sub);
    } catch (error) {
      // An expired or bad token is routine (the client refreshes and
      // reconnects); anything else is a real fault worth seeing in the logs.
      const name = (error as Error)?.name;
      if (name !== 'TokenExpiredError' && name !== 'JsonWebTokenError' && name !== 'NotBeforeError') {
        this.logger.warn(`Socket connection failed: ${error}`);
      }
      client.disconnect();
    }
  }

  async handleDisconnect(client: Socket): Promise<void> {
    const userId = client.data.userId as string | undefined;
    if (userId) await this.presence.markOffline(userId);
  }

  /// A client can optionally ping this while a specific thread is open,
  /// letting a future enhancement (e.g. "typing…" or read receipts) target
  /// just that thread's room — unused for now beyond acking the join so
  /// the client knows the socket is live.
  ///
  /// Mirrors ChatService.assertCanRead (a real
  /// ThreadParticipant row, or an admin allowed into a support thread — see
  /// adminCanAccessSupportThread) — without it,
  /// any authenticated socket could join an arbitrary thread id it merely
  /// guessed or came across and silently receive every message
  /// [broadcastMessage] emits into that thread's room, regardless of
  /// whether it's actually a participant.
  @SubscribeMessage('thread:join')
  async onJoinThread(@ConnectedSocket() client: Socket, @MessageBody() threadId: string): Promise<void> {
    if (typeof threadId !== 'string') return;
    const userId = client.data.userId as string | undefined;
    if (!userId) return;

    const membership = await this.prisma.threadParticipant.findUnique({ where: { threadId_userId: { threadId, userId } } });
    if (!membership) {
      const role = client.data.role as string | undefined;
      if (role !== 'ADMIN') return;
      const thread = await this.prisma.thread.findUnique({
        where: { id: threadId },
        select: { isSupport: true, assignedAdminId: true },
      });
      if (!thread || !(await adminCanAccessSupportThread(this.prisma, thread, userId))) return;
    }

    client.join(this.threadRoom(threadId));
  }

  /// Pushed to every participant's personal room except [senderId] right
  /// after ChatController persists a new message via ChatService.
  broadcastMessage(participantUserIds: string[], senderId: string, threadId: string, message: unknown): void {
    for (const userId of participantUserIds) {
      if (userId === senderId) continue;
      this.server.to(this.userRoom(userId)).emit('message:new', { threadId, message });
    }
    this.server.to(this.threadRoom(threadId)).emit('message:new', { threadId, message });
  }

  /// Pushed to a single user's own room — the generic counterpart to
  /// [broadcastMessage], used by NotificationsService (the single
  /// choke-point every notification, from chat/admin/payments/reports,
  /// already passes through) so any new Notification row shows up
  /// instantly as an in-app banner without a second realtime channel.
  emitToUser(userId: string, event: string, payload: unknown): void {
    this.server.to(this.userRoom(userId)).emit(event, payload);
  }

  /// Every currently-connected admin at once — for an event with no
  /// specific admin participant to target yet, like a support thread no
  /// admin has claimed. Offline admins still get the DB-backed Notification
  /// row created alongside this; this just makes an already-open Support
  /// Queue tab update live instead of waiting for a manual refresh.
  broadcastToAdmins(event: string, payload: unknown): void {
    this.server.to(this.adminRoom()).emit(event, payload);
  }

  /// Called whenever a support thread changes hands (claimed from the
  /// queue, claimed by a first reply, or transferred). Any socket in the
  /// thread's room that's no longer allowed in — not a participant, and not
  /// an admin who still passes adminCanAccessSupportThread — is removed
  /// from the room so it stops receiving that thread's live messages, and
  /// told why. Without this, a socket that joined while the thread was
  /// unclaimed stayed in the room after another admin took it over, even
  /// though every REST call was already refused.
  async evictUnauthorizedFromThread(threadId: string): Promise<void> {
    const room = this.threadRoom(threadId);
    const sockets = await this.server.in(room).fetchSockets();
    if (sockets.length === 0) return;
    const thread = await this.prisma.thread.findUnique({
      where: { id: threadId },
      select: { isSupport: true, assignedAdminId: true, participants: { select: { userId: true } } },
    });
    if (!thread) return;
    const participantIds = new Set(thread.participants.map((p) => p.userId));
    for (const socket of sockets) {
      const userId = socket.data.userId as string | undefined;
      if (userId && participantIds.has(userId)) continue;
      if (userId && socket.data.role === 'ADMIN' && (await adminCanAccessSupportThread(this.prisma, thread, userId))) {
        continue;
      }
      socket.leave(room);
      socket.emit('thread:access-revoked', { threadId });
    }
  }

  private userRoom(userId: string): string {
    return `user:${userId}`;
  }

  private threadRoom(threadId: string): string {
    return `thread:${threadId}`;
  }

  private adminRoom(): string {
    return 'admins';
  }
}
