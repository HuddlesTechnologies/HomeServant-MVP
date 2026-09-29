import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { BookingStatus, NotificationType, PaymentPlan } from '@prisma/client';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { escapeHtml } from '../common/escape-html';

const MS_PER_DAY = 24 * 60 * 60 * 1000;
/// Checked in ascending order — Array.find returns the first (smallest)
/// threshold a booking's day-count has dropped to or below, so a booking
/// gets whichever specific threshold it just crossed, not always the
/// largest one it still qualifies for. (A descending order here is a bug:
/// `daysLeft <= 30` matches before `daysLeft <= 15` or `<= 0` ever get a
/// chance to, for every daysLeft from 30 down to 0, so the 15/0-day
/// reminders would never fire — every lease would just get the 30-day
/// reminder once and nothing after.)
const REMINDER_THRESHOLDS_DAYS = [0, 15, 30] as const;

/// Monthly-plan tenants are reminded this many days before a month is due.
const MONTHLY_REMINDER_DAYS = 3;

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
    await this.sendMonthlyRentReminders();
  }

  /// Monthly-plan tenants (Booking.paymentPlan MONTHLY) with months still
  /// to pay on their current lease: a reminder [MONTHLY_REMINDER_DAYS]
  /// days before the next month is due, and — once it's overdue — one
  /// "missed payment" message to the tenant and one flag to the landlord.
  /// Each is sent once per month due (de-duped against rentPaidThrough).
  async sendMonthlyRentReminders(now = new Date()): Promise<void> {
    const leases = await this.prisma.booking.findMany({
      where: {
        status: BookingStatus.MOVED_IN,
        paymentPlan: PaymentPlan.MONTHLY,
        rentPaidThrough: { not: null },
        leaseEndDate: { gt: now },
      },
      include: {
        property: { select: { title: true, landlord: { select: { id: true, email: true } } } },
        tenant: { select: { id: true, email: true, fullName: true } },
      },
    });
    let reminded = 0;
    let flagged = 0;
    for (const booking of leases) {
      const due = booking.rentPaidThrough!;
      if (!booking.leaseEndDate || due.getTime() >= booking.leaseEndDate.getTime()) continue;
      const amount = booking.monthlyRent ? `₦${booking.monthlyRent.toLocaleString('en-US')}` : "this month's rent";
      const dueText = due.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
      const sameMonth = (sentFor: Date | null) => !!sentFor && sentFor.getTime() === due.getTime();

      if (due.getTime() < now.getTime()) {
        if (sameMonth(booking.monthlyOverdueNotifiedFor)) continue;
        const tenantBody = `Your monthly rent of ${amount} for ${booking.property.title} was due on ${dueText} and hasn't been paid. Pay it from your bookings to stay up to date.`;
        await this.notifications.create(booking.tenant.id, NotificationType.RENT_EXPIRY_REMINDER, 'Monthly rent overdue', tenantBody);
        await this.mail.send(booking.tenant.email, 'Monthly rent overdue', `<p>${escapeHtml(tenantBody)}</p>`, tenantBody);
        const name = booking.tenant.fullName?.trim() ? booking.tenant.fullName : 'Your tenant';
        const landlordBody = `${name} missed the monthly rent (${amount}) for ${booking.property.title} that was due on ${dueText}. We've reminded them.`;
        await this.notifications.create(booking.property.landlord.id, NotificationType.RENT_EXPIRY_REMINDER, 'Tenant missed a monthly payment', landlordBody);
        await this.mail.send(booking.property.landlord.email, 'Tenant missed a monthly payment', `<p>${escapeHtml(landlordBody)}</p>`, landlordBody);
        await this.prisma.booking.update({ where: { id: booking.id }, data: { monthlyOverdueNotifiedFor: due } });
        flagged++;
      } else if ((due.getTime() - now.getTime()) / MS_PER_DAY <= MONTHLY_REMINDER_DAYS && !sameMonth(booking.monthlyReminderSentFor)) {
        const body = `Your monthly rent of ${amount} for ${booking.property.title} is due on ${dueText}. You can pay it now from your bookings.`;
        await this.notifications.create(booking.tenant.id, NotificationType.RENT_EXPIRY_REMINDER, 'Monthly rent due soon', body);
        await this.mail.send(booking.tenant.email, 'Monthly rent due soon', `<p>${escapeHtml(body)}</p>`, body);
        await this.prisma.booking.update({ where: { id: booking.id }, data: { monthlyReminderSentFor: due } });
        reminded++;
      }
    }
    if (reminded + flagged > 0) this.logger.log(`Monthly rent: ${reminded} reminder(s), ${flagged} missed payment(s) flagged`);
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

  /// Sends the same 30/15/0-day-out reminder to both sides of the lease —
  /// previously tenant-only, which left a landlord with no warning that a
  /// unit was about to come back on the market. Both notifications share
  /// the one [lastRentReminderDaysOut] de-dupe field on the booking, so
  /// they're always sent (or skipped) together rather than drifting apart.
  private async sendRentExpiryReminders(): Promise<void> {
    const now = new Date();
    const active = await this.prisma.booking.findMany({
      where: { status: BookingStatus.MOVED_IN, leaseEndDate: { gte: now } },
      include: {
        property: { select: { title: true, landlord: { select: { id: true, email: true } } } },
        tenant: { select: { id: true, email: true, fullName: true } },
      },
    });

    let sent = 0;
    for (const booking of active) {
      if (!booking.leaseEndDate) continue;
      const daysLeft = Math.floor((booking.leaseEndDate.getTime() - now.getTime()) / MS_PER_DAY);
      const threshold = REMINDER_THRESHOLDS_DAYS.find((t) => daysLeft <= t);
      if (threshold === undefined || booking.lastRentReminderDaysOut === threshold) continue;

      const when = threshold === 0 ? 'today' : `in ${threshold} days`;
      const tenantTitle = 'Your lease is ending soon';
      const tenantBody = `Your lease for ${booking.property.title} ends ${when}. Renew from your bookings to keep your stay.`;
      await this.notifications.create(booking.tenant.id, NotificationType.RENT_EXPIRY_REMINDER, tenantTitle, tenantBody);
      await this.mail.send(booking.tenant.email, tenantTitle, `<p>${escapeHtml(tenantBody)}</p>`, tenantBody);

      const tenantName = booking.tenant.fullName?.trim() ? booking.tenant.fullName : 'Your tenant';
      const landlordTitle = "A tenant's lease is ending soon";
      const landlordBody = `${tenantName}'s lease for ${booking.property.title} ends ${when}.`;
      await this.notifications.create(booking.property.landlord.id, NotificationType.RENT_EXPIRY_REMINDER, landlordTitle, landlordBody);
      await this.mail.send(booking.property.landlord.email, landlordTitle, `<p>${escapeHtml(landlordBody)}</p>`, landlordBody);

      await this.prisma.booking.update({ where: { id: booking.id }, data: { lastRentReminderDaysOut: threshold } });
      sent++;
    }
    if (sent > 0) {
      this.logger.log(`Sent ${sent} rent-expiry reminder(s)`);
    }
  }
}
