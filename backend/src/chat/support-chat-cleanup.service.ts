import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';

const SUPPORT_MESSAGE_TTL_DAYS = 30;

/// "Contact Support" conversations should only last 30 days on the admin's
/// end, whether or not they've been marked resolved (a resolved one is
/// separately hidden from the *user's* own inbox immediately — see
/// ChatService.findForUser — but stays visible to admins until this cron
/// actually deletes it). Copies AccountCleanupService's exact
/// cutoff-date-`deleteMany` shape. Regular (non-support) chat threads are
/// untouched — this only ever targets `Thread.isSupport` rows.
@Injectable()
export class SupportChatCleanupService {
  private readonly logger = new Logger('SupportChatCleanup');

  constructor(private readonly prisma: PrismaService) {}

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async purgeOldSupportMessages(): Promise<void> {
    const cutoff = new Date(Date.now() - SUPPORT_MESSAGE_TTL_DAYS * 24 * 60 * 60 * 1000);
    const { count } = await this.prisma.message.deleteMany({
      where: { createdAt: { lt: cutoff }, thread: { isSupport: true } },
    });
    if (count > 0) {
      this.logger.log(`Deleted ${count} support message(s) older than ${SUPPORT_MESSAGE_TTL_DAYS} days`);
    }

    // A support thread with no messages left (every one of them purged
    // above) has nothing left to show in either inbox — clean it up too
    // rather than leaving an empty row behind indefinitely. The same
    // [cutoff] guards this: without it, a thread created via
    // openSupportThread moments before this cron runs — before the user's
    // first message is even sent — would also match `messages: { none: {} }`
    // and get deleted out from under them, breaking their very next send
    // with "Not a participant of this thread".
    const { count: threadCount } = await this.prisma.thread.deleteMany({
      where: { isSupport: true, messages: { none: {} }, createdAt: { lt: cutoff } },
    });
    if (threadCount > 0) {
      this.logger.log(`Deleted ${threadCount} emptied support thread(s)`);
    }
  }
}
