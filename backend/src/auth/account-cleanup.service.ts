import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../prisma/prisma.service';

const DEACTIVATED_ACCOUNT_TTL_DAYS = 30;

/// A deactivated account (Settings > Danger Zone > "Deactivate Account")
/// that's never logged back in to reactivate gets permanently deleted
/// after 30 days — matches the countdown shown on the deactivation
/// confirmation dialog. Runs once a day; only actually does anything to
/// accounts that have been sitting deactivated past the cutoff, so
/// running late (e.g. the service was asleep on Render's free tier) just
/// means yesterday's batch gets swept up on the next tick instead of a
/// missed run silently doing nothing.
@Injectable()
export class AccountCleanupService {
  private readonly logger = new Logger('AccountCleanup');

  constructor(private readonly prisma: PrismaService) {}

  @Cron(CronExpression.EVERY_DAY_AT_3AM)
  async purgeExpiredDeactivatedAccounts(): Promise<void> {
    const cutoff = new Date(Date.now() - DEACTIVATED_ACCOUNT_TTL_DAYS * 24 * 60 * 60 * 1000);
    const { count } = await this.prisma.user.deleteMany({
      where: { deactivatedAt: { lt: cutoff } },
    });
    if (count > 0) {
      this.logger.log(`Deleted ${count} account(s) deactivated for over ${DEACTIVATED_ACCOUNT_TTL_DAYS} days`);
    }
  }
}
