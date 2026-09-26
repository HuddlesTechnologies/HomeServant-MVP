import { Injectable, Logger } from '@nestjs/common';
import { ActivityLogType } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

const summarySelect = { id: true, email: true, fullName: true } as const;

/// Site-wide admin audit trail — every admin login and every admin
/// password change/reset writes one of these (see AuthService.login/
/// verifyLoginOtp/changePassword and AdminService.confirmAdminPasswordReset).
/// [log] never throws — a failed geolocation lookup or a write error
/// shouldn't ever block the login/password action that triggered it,
/// same reasoning as MailService.send being best-effort.
@Injectable()
export class ActivityLogService {
  private readonly logger = new Logger('ActivityLog');

  constructor(private readonly prisma: PrismaService) {}

  async log(type: ActivityLogType, opts: { actorId?: string; targetId?: string; ip?: string; reason?: string }): Promise<void> {
    try {
      const location = opts.ip ? await this.lookupLocation(opts.ip) : null;
      await this.prisma.activityLog.create({
        data: { type, actorId: opts.actorId, targetId: opts.targetId, ip: opts.ip, location, reason: opts.reason },
      });
    } catch (error) {
      this.logger.error(`Failed to write activity log (${type}): ${(error as Error).message}`);
    }
  }

  /// Best-effort city/country from a free, keyless IP-geolocation API —
  /// skipped entirely for loopback/private IPs (local dev, or a request
  /// that never passed through a real proxy) and given a short timeout
  /// so a slow/unreachable lookup never holds up the actual request.
  private async lookupLocation(ip: string): Promise<string | null> {
    if (!ip || ip === '::1' || ip === '127.0.0.1' || ip.startsWith('10.') || ip.startsWith('192.168.') || ip.startsWith('::ffff:127.')) {
      return null;
    }
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 3000);
      const response = await fetch(`http://ip-api.com/json/${encodeURIComponent(ip)}?fields=status,city,country`, {
        signal: controller.signal,
      });
      clearTimeout(timeout);
      const data = (await response.json()) as { status: string; city?: string; country?: string };
      if (data.status !== 'success') return null;
      return [data.city, data.country].filter(Boolean).join(', ') || null;
    } catch {
      return null;
    }
  }

  async findAll(page = 1, pageSize = 30, type?: ActivityLogType) {
    const where = type ? { type } : {};
    const [items, total] = await Promise.all([
      this.prisma.activityLog.findMany({
        where,
        include: { actor: { select: summarySelect }, target: { select: summarySelect } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.activityLog.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  /// [type] omitted clears every entry (the whole log); given, clears only
  /// that type. See AdminService.clearActivityLog for which one gets
  /// logged afterwards.
  async clear(type?: ActivityLogType): Promise<void> {
    await this.prisma.activityLog.deleteMany({ where: type ? { type } : {} });
  }
}
