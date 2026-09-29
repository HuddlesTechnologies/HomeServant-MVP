import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Cron, CronExpression } from '@nestjs/schedule';
import { MessageType, UserRole } from '@prisma/client';
import { MailService } from '../mail/mail.service';
import { PrismaService } from '../prisma/prisma.service';
import { escapeHtml } from '../common/escape-html';

/// How long a message sits unread before its recipient is emailed.
export const UNREAD_EMAIL_DELAY_MINUTES = 15;
/// Older than this and it's not worth an email any more (it also bounds
/// the scan after downtime).
const UNREAD_EMAIL_MAX_AGE_HOURS = 24;


/// Emails tenants, landlords and vendors about messages they haven't read
/// after [UNREAD_EMAIL_DELAY_MINUTES] — one email per conversation per run,
/// and each message at most once (Message.emailNotifiedAt). Admins are not
/// emailed here: they have the console's alerts, reminders and escalation.
@Injectable()
export class UnreadMessageEmailService {
  private readonly logger = new Logger('UnreadMessageEmail');

  constructor(
    private readonly prisma: PrismaService,
    private readonly mail: MailService,
    private readonly config: ConfigService,
  ) {}

  @Cron(CronExpression.EVERY_5_MINUTES)
  async run(now = new Date()): Promise<number> {
    const due = await this.prisma.message.findMany({
      where: {
        readAt: null,
        emailNotifiedAt: null,
        senderId: { not: null },
        type: { not: MessageType.SYSTEM },
        createdAt: {
          lte: new Date(now.getTime() - UNREAD_EMAIL_DELAY_MINUTES * 60_000),
          gte: new Date(now.getTime() - UNREAD_EMAIL_MAX_AGE_HOURS * 3_600_000),
        },
      },
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        threadId: true,
        senderId: true,
        body: true,
        type: true,
        sender: { select: { fullName: true } },
        thread: {
          select: {
            isSupport: true,
            property: { select: { title: true } },
            participants: {
              select: { user: { select: { id: true, email: true, fullName: true, role: true, deactivatedAt: true } } },
            },
          },
        },
      },
    });
    if (due.length === 0) return 0;

    // Group per (thread, recipient) so a burst of messages is one email.
    const batches = new Map<string, { to: { email: string; fullName: string | null }; messages: typeof due }>();
    for (const message of due) {
      for (const { user } of message.thread.participants) {
        if (user.id === message.senderId || user.role === UserRole.ADMIN || user.deactivatedAt) continue;
        const key = `${message.threadId}:${user.id}`;
        const batch = batches.get(key) ?? { to: user, messages: [] };
        batch.messages.push(message);
        batches.set(key, batch);
      }
    }

    let sent = 0;
    for (const { to, messages } of batches.values()) {
      const last = messages[messages.length - 1];
      const from = last.thread.isSupport ? 'HomeServant Support' : (last.sender?.fullName ?? 'Someone');
      const about = last.thread.property?.title ? ` about ${last.thread.property.title}` : '';
      const preview = last.type === MessageType.IMAGE && !last.body ? '📷 Photo' : last.body.slice(0, 200);
      const count = messages.length;
      const subject = count > 1 ? `${count} unread messages from ${from}` : `New message from ${from}`;
      const link = this.appUrl();
      const text =
        `Hi ${to.fullName ?? 'there'},\n\nYou have ${count > 1 ? `${count} unread messages` : 'an unread message'} from ${from}${about} on HomeServant:\n\n"${preview}"\n\n` +
        (link ? `Open HomeServant to reply: ${link}\n` : 'Open HomeServant to reply.\n');
      const html =
        `<p>Hi ${escapeHtml(to.fullName ?? 'there')},</p>` +
        `<p>You have ${count > 1 ? `${count} unread messages` : 'an unread message'} from <strong>${escapeHtml(from)}</strong>${escapeHtml(about)} on HomeServant:</p>` +
        `<blockquote style="border-left:3px solid #c9a227;margin:0;padding:6px 12px;color:#14213d;">${escapeHtml(preview)}</blockquote>` +
        (link ? `<p><a href="${escapeHtml(link)}">Open HomeServant to reply</a></p>` : '<p>Open HomeServant to reply.</p>');
      try {
        await this.mail.send(to.email, subject, html, text);
        sent++;
      } catch (error) {
        this.logger.warn(`Unread-message email to ${to.email} failed: ${error}`);
      }
    }

    // Marked even when a message only had admin recipients, so it isn't
    // re-scanned every run.
    await this.prisma.message.updateMany({ where: { id: { in: due.map((m) => m.id) } }, data: { emailNotifiedAt: now } });
    return sent;
  }

  /// The web app's address for the email link: APP_URL, else the first
  /// allowed CORS origin (which is the web app in production).
  private appUrl(): string | null {
    const explicit = this.config.get<string>('APP_URL');
    if (explicit) return explicit;
    const origin = this.config.get<string>('CORS_ORIGINS')?.split(',')[0]?.trim();
    return origin && !origin.includes('localhost') ? origin : null;
  }
}
