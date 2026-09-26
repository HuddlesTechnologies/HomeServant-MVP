import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { NotificationType, Prisma, ReportStatus, ReportTargetType } from '@prisma/client';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { CreateReportDto } from './dto/create-report.dto';

const summarySelect = { id: true, email: true, fullName: true } as const;

@Injectable()
export class ReportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
  ) {}

  /// A tenant can only report a property they've actually rented (an
  /// ACCEPTED booking); a buyer can only report an item they've actually
  /// bought (an order item on one of their orders) — checked here rather
  /// than left to the reporter's own honesty.
  async create(reporterId: string, dto: CreateReportDto) {
    if (dto.targetType === 'PROPERTY') {
      if (!dto.propertyId) throw new BadRequestException('propertyId is required to report a property');
      const rented = await this.prisma.booking.findFirst({
        where: { tenantId: reporterId, propertyId: dto.propertyId, status: 'ACCEPTED' },
      });
      if (!rented) throw new ForbiddenException('You can only report a property you have rented');
    } else {
      if (!dto.productId) throw new BadRequestException('productId is required to report a marketplace item');
      const purchased = await this.prisma.marketplaceOrderItem.findFirst({
        where: { productId: dto.productId, order: { buyerId: reporterId } },
      });
      if (!purchased) throw new ForbiddenException('You can only report an item you have purchased');
    }

    return this.prisma.report.create({
      data: {
        reporterId,
        targetType: dto.targetType,
        propertyId: dto.targetType === 'PROPERTY' ? dto.propertyId : undefined,
        productId: dto.targetType === 'MARKETPLACE_ITEM' ? dto.productId : undefined,
        reason: dto.reason,
      },
    });
  }

  findMine(reporterId: string) {
    return this.prisma.report.findMany({
      where: { reporterId },
      include: { property: { select: { id: true, title: true } }, product: { select: { id: true, name: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async findAll(status?: ReportStatus, page = 1, pageSize = 20) {
    const where: Prisma.ReportWhereInput = status ? { status } : {};
    const [items, total] = await Promise.all([
      this.prisma.report.findMany({
        where,
        include: {
          reporter: { select: summarySelect },
          property: { select: { id: true, title: true } },
          product: { select: { id: true, name: true, vendorId: true } },
          assignedAdmin: { select: summarySelect },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.report.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  /// Full single-report detail — reached by tapping a report row (Reports
  /// tab or the dashboard's activity feed). Same include shape as
  /// [findAll] so the client's existing `AdminReport.fromApi` parses it
  /// unchanged.
  async findOne(id: string) {
    const report = await this.prisma.report.findUnique({
      where: { id },
      include: {
        reporter: { select: summarySelect },
        property: { select: { id: true, title: true } },
        product: { select: { id: true, name: true, vendorId: true } },
        assignedAdmin: { select: summarySelect },
      },
    });
    if (!report) throw new NotFoundException('Report not found');
    return report;
  }

  /// Backs the admin console's report notification badges — the combined
  /// Reports-tab count when [targetType] is omitted, or just the
  /// property-/marketplace-targeted slice for the Properties/Marketplace
  /// nav badges.
  countOpen(targetType?: ReportTargetType): Promise<number> {
    return this.prisma.report.count({ where: { status: 'OPEN', ...(targetType ? { targetType } : {}) } });
  }

  async setStatus(id: string, status: ReportStatus) {
    await this.requireReport(id);
    return this.prisma.report.update({ where: { id }, data: { status } });
  }

  /// Hands a report off to another admin, "the way Namecheap support does
  /// it" — the new assignee gets an email and an in-app notification.
  /// Moves an OPEN report to IN_PROGRESS since someone is now on it;
  /// leaves RESOLVED alone (transferring a resolved report is just
  /// reassigning ownership of the record, not reopening it).
  async transfer(id: string, toAdminId: string) {
    const report = await this.requireReport(id);
    const admin = await this.prisma.user.findUnique({ where: { id: toAdminId } });
    if (!admin || admin.role !== 'ADMIN') throw new NotFoundException('Admin not found');

    const updated = await this.prisma.report.update({
      where: { id },
      data: { assignedAdminId: toAdminId, status: report.status === 'OPEN' ? 'IN_PROGRESS' : report.status },
    });
    await this.notifications.create(
      toAdminId,
      NotificationType.REPORT_ASSIGNED,
      'A report was assigned to you',
      'Another admin transferred a report to you — open Reports in the admin console to review it.',
    );
    await this.mail.send(
      admin.email,
      'A HomeServant report was assigned to you',
      '<p>Another admin transferred a report to you — open Reports in the admin console to review it.</p>',
      'Another admin transferred a report to you — open Reports in the admin console to review it.',
    );
    return updated;
  }

  private async requireReport(id: string) {
    const report = await this.prisma.report.findUnique({ where: { id } });
    if (!report) throw new NotFoundException('Report not found');
    return report;
  }
}
