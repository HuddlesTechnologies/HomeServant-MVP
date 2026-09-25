import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { BookingStatus, NotificationType } from '@prisma/client';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';

const MS_PER_DAY = 24 * 60 * 60 * 1000;
/// Checked in this order (largest first) — a booking gets whichever
/// threshold its current day-count has just crossed, not all of them.
const REMINDER_THRESHOLDS_DAYS = [30, 15, 0] as const;

/// Runs once a day (mirrors AccountCleanupService's own @Cron pattern) and
/// does two unrelated-but-adjacent things to every MOVED_IN lease:
///
/// 1. Auto-relists a property whose lease has run past leaseEndDate with
///    no renewal — flips Property.isOccupied back to false so the listing
///    is bookable again. NOTE: this deliberately does *not* change the
///    Booking's own `status` away from MOVED_IN — BookingStatus has no
///    terminal "lease ended" value today, the task that commissioned this
///    file explicitly said not to reuse DECLINED and not to invent a new
///    enum value without checking first, so this is flagged rather than
///    silently picked. See the handback report for the exact ask.
/// 2. Sends a 30/15/0-day-before rent-expiry reminder (in-app + email) to
///    each MOVED_IN booking's tenant — de-duped via
///    Booking.lastRentReminderDaysOut (a schema addition beyond Phase 1,
///    also flagged in the report) so a daily tick doesn't re-send the same
///    threshold every day it's still true.
@Injectable()
export class LeaseLifecycleService {
  private readonly logger = new Logger('LeaseLifecycle');

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
  ) {}

  @Cron(CronExpression.EVERY_DAY_AT_4AM)
  async run(): Promise<void> {
    await this.autoRelistExpiredLeases();
    await this.sendRentExpiryReminders();
  }

  private async autoRelistExpiredLeases(): Promise<void> {
    const now = new Date();
    const expired = await this.prisma.booking.findMany({
      where: { status: BookingStatus.MOVED_IN, leaseEndDate: { lt: now } },
      include: { property: { select: { id: true, isOccupied: true, title: true } } },
    });

    let relisted = 0;
    for (const booking of expired) {
      if (!booking.property.isOccupied) continue; // already relisted (or a renewal beat the cron to it)
      await this.prisma.property.update({ where: { id: booking.property.id }, data: { isOccupied: false } });
      relisted++;
    }
    if (relisted > 0) {
      this.logger.log(`Auto-relisted ${relisted} propert${relisted === 1 ? 'y' : 'ies'} whose lease ended without renewal`);
    }
  }

  private async sendRentExpiryReminders(): Promise<void> {
    const now = new Date();
    const active = await this.prisma.booking.findMany({
      where: { status: BookingStatus.MOVED_IN, leaseEndDate: { gte: now } },
      include: { property: { select: { title: true } }, tenant: { select: { id: true, email: true } } },
    });

    let sent = 0;
    for (const booking of active) {
      if (!booking.leaseEndDate) continue;
      const daysLeft = Math.floor((booking.leaseEndDate.getTime() - now.getTime()) / MS_PER_DAY);
      const threshold = REMINDER_THRESHOLDS_DAYS.find((t) => daysLeft <= t);
      if (threshold === undefined || booking.lastRentReminderDaysOut === threshold) continue;

      const when = threshold === 0 ? 'today' : `in ${threshold} days`;
      const title = 'Your lease is ending soon';
      const body = `Your lease for ${booking.property.title} ends ${when}. Renew from your bookings to keep your stay.`;
      await this.notifications.create(booking.tenant.id, NotificationType.RENT_EXPIRY_REMINDER, title, body);
      await this.mail.send(booking.tenant.email, title, `<p>${body}</p>`, body);
      await this.prisma.booking.update({ where: { id: booking.id }, data: { lastRentReminderDaysOut: threshold } });
      sent++;
    }
    if (sent > 0) {
      this.logger.log(`Sent ${sent} rent-expiry reminder(s)`);
    }
  }
}
