import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { NotificationType } from '@prisma/client';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';

/// Follow-up alerts so a support conversation can't quietly go unanswered:
///
/// - **Unclaimed reminder:** a support thread nobody has picked up
///   [unclaimedReminderMinutes] after its first message gets one "still
///   waiting" alert to every admin (audible for on-duty admins). Once per
///   thread (Thread.unclaimedReminderAt).
/// - **Reply escalation:** a claimed thread whose latest message is from the
///   customer and has gone unanswered for [replyEscalationMinutes] alerts
///   every super admin (except the handler), who can then reassign it. Once
///   per unanswered stretch (Thread.replyEscalatedAt): a newer customer
///   message after that can trigger the next one.
///
/// Both delays come from SUPPORT_UNCLAIMED_REMINDER_MINUTES (default 5) and
/// SUPPORT_REPLY_ESCALATION_MINUTES (default 10). Runs every minute; if the
/// server was asleep (e.g. Render's free tier), overdue alerts go out on
/// the first run after it wakes.
@Injectable()
export class SupportAlertsService {
  private readonly logger = new Logger('SupportAlerts');
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly config: ConfigService,
  ) {}

  private minutes(key: string, fallback: number): number {
    const value = Number(this.config.get<string>(key));
    return Number.isFinite(value) && value > 0 ? value : fallback;
  }

  private get unclaimedReminderMinutes(): number {
    return this.minutes('SUPPORT_UNCLAIMED_REMINDER_MINUTES', 5);
  }

  private get replyEscalationMinutes(): number {
    return this.minutes('SUPPORT_REPLY_ESCALATION_MINUTES', 10);
  }

  @Cron(CronExpression.EVERY_MINUTE)
  async run(): Promise<void> {
    // A slow run (many threads, slow DB) must not overlap the next tick
    // and double-send.
    if (this.running) return;
    this.running = true;
    try {
      await this.remindUnclaimed();
      await this.escalateUnanswered();
    } catch (error) {
      this.logger.error(`Support alerts run failed: ${error}`);
    } finally {
      this.running = false;
    }
  }

  private async remindUnclaimed(): Promise<void> {
    const cutoff = new Date(Date.now() - this.unclaimedReminderMinutes * 60_000);
    const threads = await this.prisma.thread.findMany({
      where: {
        isSupport: true,
        status: 'OPEN',
        assignedAdminId: null,
        unclaimedReminderAt: null,
        messages: { some: { createdAt: { lt: cutoff } } },
      },
      include: { participants: { include: { user: { select: { fullName: true } } } } },
      take: 50,
    });
    if (threads.length === 0) return;
    const admins = await this.prisma.user.findMany({ where: { role: 'ADMIN' }, select: { id: true, adminOnDuty: true } });

    for (const thread of threads) {
      // Claim the reminder first, so a crash mid-send can't repeat it.
      const { count } = await this.prisma.thread.updateMany({
        where: { id: thread.id, unclaimedReminderAt: null, assignedAdminId: null },
        data: { unclaimedReminderAt: new Date() },
      });
      if (count === 0) continue;
      const customer = thread.participants[0]?.user?.fullName ?? 'A customer';
      await Promise.all(
        admins.map((admin) =>
          this.notifications.create(
            admin.id,
            NotificationType.NEW_MESSAGE,
            'Support conversation still waiting',
            `${customer} has been waiting over ${this.unclaimedReminderMinutes} minutes for an admin to pick up their conversation.`,
            thread.id,
            !admin.adminOnDuty,
          ),
        ),
      );
    }
  }

  private async escalateUnanswered(): Promise<void> {
    const cutoff = new Date(Date.now() - this.replyEscalationMinutes * 60_000);
    const threads = await this.prisma.thread.findMany({
      where: { isSupport: true, status: 'OPEN', assignedAdminId: { not: null } },
      include: {
        assignedAdmin: { select: { fullName: true } },
        messages: {
          orderBy: { createdAt: 'desc' },
          take: 1,
          include: { sender: { select: { role: true, fullName: true } } },
        },
      },
      take: 200,
    });

    const waiting = threads.filter((thread) => {
      const latest = thread.messages[0];
      if (!latest || latest.createdAt >= cutoff) return false;
      // Waiting on the admin only if the customer spoke last.
      if (!latest.sender || latest.sender.role === 'ADMIN') return false;
      return !thread.replyEscalatedAt || thread.replyEscalatedAt < latest.createdAt;
    });
    if (waiting.length === 0) return;

    const superAdmins = await this.prisma.user.findMany({
      where: { role: 'ADMIN', adminLevel: 'SUPER_ADMIN' },
      select: { id: true, adminOnDuty: true },
    });

    for (const thread of waiting) {
      const latest = thread.messages[0];
      const { count } = await this.prisma.thread.updateMany({
        where: {
          id: thread.id,
          OR: [{ replyEscalatedAt: null }, { replyEscalatedAt: { lt: latest.createdAt } }],
        },
        data: { replyEscalatedAt: new Date() },
      });
      if (count === 0) continue;
      const customer = latest.sender?.fullName ?? 'A customer';
      const handler = thread.assignedAdmin?.fullName ?? 'the assigned admin';
      await Promise.all(
        superAdmins
          .filter((admin) => admin.id !== thread.assignedAdminId)
          .map((admin) =>
            this.notifications.create(
              admin.id,
              NotificationType.NEW_MESSAGE,
              'Customer waiting for a reply',
              `${customer} has been waiting over ${this.replyEscalationMinutes} minutes for ${handler} to reply. Open it to reassign.`,
              thread.id,
              !admin.adminOnDuty,
            ),
          ),
      );
    }
  }
}
