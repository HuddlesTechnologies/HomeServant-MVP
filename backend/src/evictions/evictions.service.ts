import { BadRequestException, ConflictException, ForbiddenException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { AdminLevel, BookingStatus, EvictionStatus, NotificationType, Prisma, UserRole } from '@prisma/client';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { escapeHtml } from '../common/escape-html';
import { EMAIL_PROPERTY_SELECT, propertyEmailDetails } from '../common/property-email';

const include = {
  booking: {
    select: {
      id: true,
      status: true,
      leaseStartDate: true,
      leaseEndDate: true,
      priceSnapshot: true,
      priceUnitSnapshot: true,
      property: { select: { id: true, imageUrl: true, ...EMAIL_PROPERTY_SELECT } },
    },
  },
  landlord: { select: { id: true, fullName: true, email: true, phoneNumber: true } },
  tenant: { select: { id: true, fullName: true, email: true, phoneNumber: true } },
  reviewedBy: { select: { id: true, fullName: true, email: true } },
} satisfies Prisma.EvictionRequestInclude;

/// Landlord-initiated evictions. A landlord can only *ask*: the tenancy is
/// untouched until a SUPER_ADMIN reviews the case and approves it, at which
/// point the lease ends today and the property is listed again (the same
/// end state the lease-lifecycle cron reaches when a lease simply expires).
/// The tenant is told as soon as a request is filed and can add their side
/// of the story for the reviewer.
@Injectable()
export class EvictionsService {
  private readonly logger = new Logger('Evictions');

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
  ) {}

  async create(landlordId: string, bookingId: string, reason: string) {
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      include: { property: { select: { landlordId: true, ...EMAIL_PROPERTY_SELECT } }, tenant: { select: { id: true, email: true } } },
    });
    if (!booking || booking.property.landlordId !== landlordId) throw new NotFoundException('Tenancy not found');
    const now = new Date();
    if (booking.status !== BookingStatus.MOVED_IN || (booking.leaseEndDate && booking.leaseEndDate <= now)) {
      throw new BadRequestException('You can only request an eviction for a tenant who currently lives in the property');
    }
    const request = await this.prisma.$transaction(async (tx) => {
      const pending = await tx.evictionRequest.findFirst({ where: { bookingId, status: EvictionStatus.PENDING } });
      if (pending) throw new ConflictException('There is already an eviction request under review for this tenant');
      return tx.evictionRequest.create({
        data: { bookingId, landlordId, tenantId: booking.tenantId, reason: reason.trim() },
        include,
      });
    });

    const title = booking.property.title;
    await this.notifications.create(
      booking.tenantId,
      NotificationType.BOOKING_STATUS,
      'Eviction request filed',
      `Your landlord has asked HomeServant to end your tenancy at ${title}. Nothing changes unless our team approves it — open Booking History to read the reason and add your side.`,
    );
    await this.mail.send(
      booking.tenant.email,
      `Your landlord has requested to end your tenancy at "${title}"`,
      `<p>Your landlord has asked HomeServant to end your tenancy at <strong>${escapeHtml(title)}</strong>.</p>` +
        `<p><strong>Reason given:</strong> ${escapeHtml(request.reason)}</p>` +
        `<p>Nothing changes unless a HomeServant super admin reviews the case and approves it. You can add your side of the story from Booking History in the app.</p>` +
        propertyEmailDetails(booking.property).html,
      `Your landlord has asked HomeServant to end your tenancy at "${title}".\n\nReason given: ${request.reason}\n\nNothing changes unless a HomeServant super admin reviews the case and approves it. You can add your side of the story from Booking History in the app.` +
        propertyEmailDetails(booking.property).text,
    );
    // Tell every super admin a case is waiting for review.
    const superAdmins = await this.prisma.user.findMany({
      where: { role: UserRole.ADMIN, adminLevel: AdminLevel.SUPER_ADMIN, deactivatedAt: null },
      select: { id: true },
    });
    for (const admin of superAdmins) {
      await this.notifications.create(
        admin.id,
        NotificationType.BOOKING_STATUS,
        'Eviction request to review',
        `${request.landlord.fullName ?? 'A landlord'} asked to evict ${request.tenant.fullName ?? 'a tenant'} from ${title}. Open More → Eviction Requests.`,
      );
    }
    return request;
  }

  /// Every request the user is a party to, newest first — the landlord's
  /// filed ones or the tenant's received ones.
  findMine(userId: string) {
    return this.prisma.evictionRequest.findMany({
      where: { OR: [{ landlordId: userId }, { tenantId: userId }] },
      include,
      orderBy: { createdAt: 'desc' },
    });
  }

  async cancel(landlordId: string, id: string) {
    const request = await this.findPendingFor(id);
    if (request.landlordId !== landlordId) throw new ForbiddenException('Only the landlord who filed this request can withdraw it');
    const updated = await this.prisma.evictionRequest.update({ where: { id }, data: { status: EvictionStatus.CANCELLED }, include });
    await this.notifications.create(
      request.tenantId,
      NotificationType.BOOKING_STATUS,
      'Eviction request withdrawn',
      `Your landlord withdrew their request to end your tenancy at ${updated.booking.property.title}.`,
    );
    return updated;
  }

  async respond(tenantId: string, id: string, response: string) {
    const request = await this.findPendingFor(id);
    if (request.tenantId !== tenantId) throw new ForbiddenException('Only the tenant can respond to this request');
    return this.prisma.evictionRequest.update({
      where: { id },
      data: { tenantResponse: response.trim(), tenantRespondedAt: new Date() },
      include,
    });
  }

  findForAdmin(status?: string) {
    const valid = Object.values(EvictionStatus) as string[];
    const where = status && valid.includes(status) ? { status: status as EvictionStatus } : {};
    return this.prisma.evictionRequest.findMany({ where, include, orderBy: { createdAt: 'desc' }, take: 200 });
  }

  pendingCount() {
    return this.prisma.evictionRequest.count({ where: { status: EvictionStatus.PENDING } });
  }

  async review(adminId: string, id: string, decision: 'APPROVE' | 'REJECT', note?: string) {
    const cleanNote = note?.trim() || null;
    if (decision === 'REJECT' && (!cleanNote || cleanNote.length < 10)) {
      throw new BadRequestException('Explain why the request is rejected (at least 10 characters) — both parties see it');
    }
    const now = new Date();
    const updated = await this.prisma.$transaction(async (tx) => {
      // Claim the decision atomically so two super admins can't both decide.
      const claimed = await tx.evictionRequest.updateMany({
        where: { id, status: EvictionStatus.PENDING },
        data: {
          status: decision === 'APPROVE' ? EvictionStatus.APPROVED : EvictionStatus.REJECTED,
          reviewedById: adminId,
          reviewNote: cleanNote,
          reviewedAt: now,
        },
      });
      if (claimed.count === 0) {
        const exists = await tx.evictionRequest.findUnique({ where: { id }, select: { id: true } });
        if (!exists) throw new NotFoundException('Eviction request not found');
        throw new ConflictException('This request has already been decided or withdrawn');
      }
      const request = await tx.evictionRequest.findUniqueOrThrow({ where: { id }, include });
      if (decision === 'APPROVE') {
        // End the lease today and put the unit back on the market — the same
        // end state as an expired lease (see LeaseLifecycleService).
        await tx.booking.update({ where: { id: request.bookingId }, data: { leaseEndDate: now } });
        await tx.property.update({ where: { id: request.booking.property.id }, data: { isOccupied: false } });
      }
      return request;
    });

    const title = updated.booking.property.title;
    const approved = decision === 'APPROVE';
    const noteLine = cleanNote ? ` Note from HomeServant: ${cleanNote}` : '';
    const tenantBody = approved
      ? `After reviewing the case, HomeServant approved your landlord's request to end your tenancy at ${title}. Your lease has ended.${noteLine}`
      : `HomeServant reviewed your landlord's request to end your tenancy at ${title} and rejected it. Your tenancy continues as normal.${noteLine}`;
    const landlordBody = approved
      ? `Your eviction request for ${title} was approved. The lease has ended and the property is listed again.${noteLine}`
      : `Your eviction request for ${title} was rejected. The tenancy continues.${noteLine}`;
    const heading = approved ? 'Eviction request approved' : 'Eviction request rejected';
    await this.notifications.create(updated.tenantId, NotificationType.BOOKING_STATUS, heading, tenantBody);
    await this.notifications.create(updated.landlordId, NotificationType.BOOKING_STATUS, heading, landlordBody);
    for (const [to, body] of [
      [updated.tenant.email, tenantBody],
      [updated.landlord.email, landlordBody],
    ] as const) {
      const details = propertyEmailDetails(updated.booking.property);
      await this.mail.send(to, `${heading}: "${title}"`, `<p>${escapeHtml(body)}</p>${details.html}`, body + details.text);
    }
    this.logger.log(`Eviction ${id} ${approved ? 'approved' : 'rejected'} by ${adminId}`);
    return updated;
  }

  private async findPendingFor(id: string) {
    const request = await this.prisma.evictionRequest.findUnique({ where: { id } });
    if (!request) throw new NotFoundException('Eviction request not found');
    if (request.status !== EvictionStatus.PENDING) throw new ConflictException('This request has already been decided or withdrawn');
    return request;
  }
}

