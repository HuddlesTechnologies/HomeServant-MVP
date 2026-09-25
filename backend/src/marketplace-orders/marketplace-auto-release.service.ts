import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { FulfillmentMethod, OrderItemStatus, PaymentStatus, ReportStatus, ReportTargetType } from '@prisma/client';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const AUTO_RELEASE_DAYS = 7;

/// A buyer who never clicks "received" shouldn't strand a vendor's payout
/// forever — this daily cron (mirrors AccountCleanupService/
/// LeaseLifecycleService's own @Cron pattern) auto-releases a held
/// marketplace payment 7 days after the item was marked shipped (DELIVERY
/// fulfillment) or 7 days after payment (PICKUP fulfillment, which never
/// ships) — unless the buyer has filed an open/in-progress Report against
/// that product in the meantime, in which case it's left held for admin
/// review instead of being silently released out from under a dispute.
@Injectable()
export class MarketplaceAutoReleaseService {
  private readonly logger = new Logger('MarketplaceAutoRelease');

  constructor(
    private readonly prisma: PrismaService,
    private readonly payments: PaymentsService,
  ) {}

  @Cron(CronExpression.EVERY_DAY_AT_5AM)
  async run(): Promise<void> {
    const cutoff = new Date(Date.now() - AUTO_RELEASE_DAYS * MS_PER_DAY);

    const candidates = await this.prisma.marketplaceOrderItem.findMany({
      where: {
        status: OrderItemStatus.PENDING,
        payment: { status: PaymentStatus.PAID_HELD },
        OR: [
          { fulfillment: FulfillmentMethod.DELIVERY, shippedAt: { lt: cutoff } },
          { fulfillment: FulfillmentMethod.PICKUP, payment: { status: PaymentStatus.PAID_HELD, paidAt: { lt: cutoff } } },
        ],
      },
      select: { id: true, productId: true },
    });

    let released = 0;
    let skipped = 0;
    for (const item of candidates) {
      const openReport = await this.prisma.report.findFirst({
        where: {
          targetType: ReportTargetType.MARKETPLACE_ITEM,
          productId: item.productId,
          status: { in: [ReportStatus.OPEN, ReportStatus.IN_PROGRESS] },
        },
        select: { id: true },
      });
      if (openReport) {
        skipped++;
        continue;
      }
      await this.payments.autoReleaseOrderItem(item.id);
      released++;
    }

    if (released > 0 || skipped > 0) {
      this.logger.log(`Auto-released ${released} order item payment(s); skipped ${skipped} with an open report pending admin review`);
    }
  }
}
