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
    const candidates = await this.prisma.user.findMany({
      where: { deactivatedAt: { lt: cutoff } },
      select: {
        id: true,
        vendorProfile: { select: { orderItems: { select: { id: true }, take: 1 } } },
        bookings: { select: { id: true }, where: { status: { in: ['ACCEPTED', 'PAID', 'MOVED_IN'] } }, take: 1 },
      },
    });

    // A vendor with any order-item history cascades that history away for
    // OTHER buyers if purged (MarketplaceOrderItem.vendor is onDelete:
    // Cascade) — and a tenant with an active/paid/moved-in lease has a
    // real tenancy depending on their account existing. Neither should be
    // silently auto-deleted; both need an admin's explicit hand via the
    // console instead.
    const ids = candidates
      .filter((u) => (u.vendorProfile?.orderItems.length ?? 0) === 0 && u.bookings.length === 0)
      .map((u) => u.id);
    const skipped = candidates.length - ids.length;

    if (ids.length > 0) {
      const { count } = await this.prisma.user.deleteMany({ where: { id: { in: ids } } });
      this.logger.log(`Deleted ${count} account(s) deactivated for over ${DEACTIVATED_ACCOUNT_TTL_DAYS} days`);
    }
    if (skipped > 0) {
      this.logger.log(
        `Skipped ${skipped} deactivated account(s) past the cutoff — vendor order history or an active tenancy depends on them; needs admin removal instead`,
      );
    }
  }
}
