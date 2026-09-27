import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as webpush from 'web-push';
import { PrismaService } from '../prisma/prisma.service';

export interface PushPayload {
  title: string;
  body: string;
  /// Same tag the in-tab browser notification uses (thread id, else the
  /// notification id), so the browser replaces rather than duplicates.
  tag: string;
  url?: string;
}

/// Web Push: notifications that reach a user's browser even when the site
/// isn't open. Needs VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY (generate once
/// with `npx web-push generate-vapid-keys`) and VAPID_SUBJECT (a
/// `mailto:` address); without them push is simply off and everything
/// else works as before.
@Injectable()
export class PushService {
  private readonly logger = new Logger('Push');
  readonly publicKey: string | null;

  constructor(
    private readonly prisma: PrismaService,
    config: ConfigService,
  ) {
    const publicKey = config.get<string>('VAPID_PUBLIC_KEY');
    const privateKey = config.get<string>('VAPID_PRIVATE_KEY');
    const subject = config.get<string>('VAPID_SUBJECT', 'mailto:support@homeservant.app');
    if (publicKey && privateKey) {
      webpush.setVapidDetails(subject, publicKey, privateKey);
      this.publicKey = publicKey;
    } else {
      this.publicKey = null;
    }
  }

  get enabled(): boolean {
    return this.publicKey !== null;
  }

  /// Registers (or moves to [userId]) this browser's subscription — an
  /// endpoint belongs to one browser, so whoever last signed in there owns it.
  async subscribe(userId: string, endpoint: string, p256dh: string, auth: string): Promise<void> {
    await this.prisma.pushSubscription.upsert({
      where: { endpoint },
      create: { userId, endpoint, p256dh, auth },
      update: { userId, p256dh, auth },
    });
  }

  /// Called on sign-out so the next person to use this browser doesn't
  /// get the previous user's notifications.
  async unsubscribe(userId: string, endpoint: string): Promise<void> {
    await this.prisma.pushSubscription.deleteMany({ where: { userId, endpoint } });
  }

  /// Best-effort: never throws. Subscriptions the push service reports as
  /// gone (404/410 — the user revoked permission or cleared site data) are
  /// deleted.
  async sendToUser(userId: string, payload: PushPayload): Promise<void> {
    if (!this.enabled) return;
    const subscriptions = await this.prisma.pushSubscription.findMany({ where: { userId } });
    await Promise.all(
      subscriptions.map(async (sub) => {
        try {
          await webpush.sendNotification(
            { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
            JSON.stringify(payload),
            { TTL: 60 * 60 * 24 },
          );
        } catch (error) {
          const status = (error as { statusCode?: number }).statusCode;
          if (status === 404 || status === 410) {
            await this.prisma.pushSubscription.delete({ where: { id: sub.id } }).catch(() => undefined);
          } else {
            this.logger.warn(`Push to ${userId} failed: ${status ?? error}`);
          }
        }
      }),
    );
  }
}
