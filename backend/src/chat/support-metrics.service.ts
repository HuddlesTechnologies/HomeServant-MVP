import { Injectable } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { PresenceService } from './presence.service';

/// Lagos time (UTC+1, no daylight saving) for "busiest hours/days".
const LOCAL_OFFSET_HOURS = 1;

function minutesBetween(from: Date | null, to: Date | null): number | null {
  return from && to ? Math.max(0, (to.getTime() - from.getTime()) / 60_000) : null;
}

function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return Math.round(sorted[index] * 10) / 10;
}

function average(values: number[]): number | null {
  return values.length === 0 ? null : Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 10) / 10;
}

/// The super-admin support dashboard: how fast customers get a human, how
/// quickly things get resolved, what they're about, who's handling them,
/// when it's busiest, and how customers rate it. Built from SupportChatStat
/// (which outlives the 30-day message cleanup) plus live queue state.
@Injectable()
export class SupportMetricsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly presence: PresenceService,
  ) {}

  async metrics(days: number) {
    const now = new Date();
    const since = new Date(now.getTime() - days * 86_400_000);
    const [stats, admins, waiting] = await Promise.all([
      this.prisma.supportChatStat.findMany({ where: { createdAt: { gte: since } }, take: 20_000 }),
      this.prisma.user.findMany({
        where: { role: UserRole.ADMIN, deactivatedAt: null },
        select: { id: true, fullName: true, email: true, adminLevel: true, adminOnDuty: true },
      }),
      this.prisma.thread.findMany({
        where: { isSupport: true, status: 'OPEN', assignedAdminId: null, messages: { some: {} } },
        select: { createdAt: true },
      }),
    ]);
    const openByAdmin = await this.prisma.thread.groupBy({
      by: ['assignedAdminId'],
      where: { isSupport: true, status: 'OPEN', assignedAdminId: { not: null } },
      _count: true,
    });
    const openLoad = new Map(openByAdmin.map((o) => [o.assignedAdminId, o._count]));

    // Only conversations where the customer actually wrote count towards timings.
    const firstResponse = (s: (typeof stats)[number]) => minutesBetween(s.firstCustomerMessageAt, s.firstResponseAt);
    const resolution = (s: (typeof stats)[number]) => minutesBetween(s.firstCustomerMessageAt ?? s.createdAt, s.resolvedAt);
    const summarise = (rows: typeof stats) => {
      const responses = rows.map(firstResponse).filter((v): v is number => v !== null);
      const resolutions = rows.map(resolution).filter((v): v is number => v !== null);
      const ratings = rows.map((r) => r.rating).filter((v): v is number => v !== null);
      return {
        conversations: rows.length,
        resolved: rows.filter((r) => r.resolvedAt).length,
        medianFirstResponseMinutes: percentile(responses, 50),
        p90FirstResponseMinutes: percentile(responses, 90),
        medianResolutionMinutes: percentile(resolutions, 50),
        averageRating: average(ratings),
        ratings: ratings.length,
        transferred: rows.filter((r) => r.transferCount > 0).length,
        neverAnswered: rows.filter((r) => r.firstCustomerMessageAt && !r.firstResponseAt).length,
        endedByCustomer: rows.filter((r) => r.closedByCustomer).length,
      };
    };

    const topics = [...new Set(stats.map((s) => s.topic ?? 'UNSPECIFIED'))];
    const byTopic = topics
      .map((topic) => ({ topic, ...summarise(stats.filter((s) => (s.topic ?? 'UNSPECIFIED') === topic)) }))
      .sort((a, b) => b.conversations - a.conversations);

    const byAdmin = admins
      .map((admin) => {
        const firstReplies = stats.filter((s) => s.firstResponderId === admin.id);
        const resolvedRows = stats.filter((s) => s.resolvedById === admin.id);
        const responses = firstReplies.map(firstResponse).filter((v): v is number => v !== null);
        const ratings = resolvedRows.map((r) => r.rating).filter((v): v is number => v !== null);
        return {
          id: admin.id,
          name: admin.fullName?.trim() || admin.email,
          level: admin.adminLevel,
          onDuty: admin.adminOnDuty,
          online: this.presence.isOnline(admin.id),
          openNow: openLoad.get(admin.id) ?? 0,
          firstReplies: firstReplies.length,
          resolved: resolvedRows.length,
          medianFirstResponseMinutes: percentile(responses, 50),
          averageRating: average(ratings),
          ratings: ratings.length,
        };
      })
      .sort((a, b) => b.resolved - a.resolved || b.firstReplies - a.firstReplies);

    const byHour = Array.from({ length: 24 }, () => 0);
    const byWeekday = Array.from({ length: 7 }, () => 0); // Monday first
    for (const s of stats) {
      const at = s.firstCustomerMessageAt ?? s.createdAt;
      const local = new Date(at.getTime() + LOCAL_OFFSET_HOURS * 3_600_000);
      byHour[local.getUTCHours()]++;
      byWeekday[(local.getUTCDay() + 6) % 7]++;
    }

    const byDay = new Map<string, { date: string; conversations: number; resolved: number }>();
    for (let d = 0; d < days; d++) {
      const date = new Date(since.getTime() + (d + 1) * 86_400_000).toISOString().slice(0, 10);
      byDay.set(date, { date, conversations: 0, resolved: 0 });
    }
    for (const s of stats) {
      const created = byDay.get(s.createdAt.toISOString().slice(0, 10));
      if (created) created.conversations++;
      if (s.resolvedAt) {
        const day = byDay.get(s.resolvedAt.toISOString().slice(0, 10));
        if (day) day.resolved++;
      }
    }

    const nameById = new Map(admins.map((a) => [a.id, a.fullName?.trim() || a.email]));
    const recentRatings = stats
      .filter((s) => s.rating !== null && s.ratedAt)
      .sort((a, b) => b.ratedAt!.getTime() - a.ratedAt!.getTime())
      .slice(0, 10)
      .map((s) => ({
        rating: s.rating,
        comment: s.ratingComment,
        topic: s.topic,
        ratedAt: s.ratedAt,
        adminName: s.resolvedById ? (nameById.get(s.resolvedById) ?? 'A former admin') : null,
      }));

    const oldestWait = waiting.reduce<Date | null>((oldest, t) => (!oldest || t.createdAt < oldest ? t.createdAt : oldest), null);
    return {
      days,
      generatedAt: now,
      live: {
        waiting: waiting.length,
        oldestWaitMinutes: oldestWait ? Math.round(minutesBetween(oldestWait, now)!) : null,
        adminsAvailable: admins.filter((a) => a.adminOnDuty && this.presence.isOnline(a.id)).length,
        openAssigned: [...openLoad.values()].reduce((a, b) => a + b, 0),
      },
      totals: summarise(stats),
      byTopic,
      byAdmin,
      byHour,
      byWeekday,
      byDay: [...byDay.values()],
      recentRatings,
    };
  }
}
