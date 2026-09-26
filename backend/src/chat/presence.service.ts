import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

/// Tracks who's currently connected — an in-memory count of open sockets
/// per user (not just a boolean) since the same account can have more than
/// one socket at once (two tabs, phone + web), so the first tab closing
/// shouldn't flip the account to "offline" while a second tab is still
/// open. Per-process only: this resets on a deploy/restart and wouldn't be
/// shared across multiple backend instances if this ever runs behind a
/// load balancer with more than one — acceptable for this app's current
/// single-instance scale.
@Injectable()
export class PresenceService {
  private readonly socketCountByUserId = new Map<string, number>();

  constructor(private readonly prisma: PrismaService) {}

  isOnline(userId: string): boolean {
    return (this.socketCountByUserId.get(userId) ?? 0) > 0;
  }

  markOnline(userId: string): void {
    this.socketCountByUserId.set(userId, (this.socketCountByUserId.get(userId) ?? 0) + 1);
  }

  /// Persists `lastActiveAt` only once the user's *last* socket actually
  /// disconnects — not on every socket, so briefly reconnecting (e.g. a
  /// screen navigation that tears down and rebuilds the socket) doesn't
  /// stamp a "last active" time while the user is still using the app.
  async markOffline(userId: string): Promise<void> {
    const remaining = (this.socketCountByUserId.get(userId) ?? 1) - 1;
    if (remaining > 0) {
      this.socketCountByUserId.set(userId, remaining);
      return;
    }
    this.socketCountByUserId.delete(userId);
    await this.prisma.user.update({ where: { id: userId }, data: { lastActiveAt: new Date() } }).catch(() => {
      // Best-effort — a user deleted between connecting and disconnecting
      // shouldn't throw out of a socket teardown handler.
    });
  }
}
