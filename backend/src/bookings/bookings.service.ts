import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BookingStatus, NotificationType, PropertyCategory } from '@prisma/client';
import { NotificationsService } from '../notifications/notifications.service';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';
import { CreateBookingDto } from './dto/create-booking.dto';
import { ProposeInspectionDto } from './dto/propose-inspection.dto';

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

@Injectable()
export class BookingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly payments: PaymentsService,
  ) {}

  /// A Shortlet booking is unaffected by the pay/inspect reversal below —
  /// it still needs the landlord's accept/decline (date-conflict checked
  /// in `respond`) before the tenant can pay, same as before.
  ///
  /// A non-Shortlet rental now charges the tenant immediately: no
  /// `requestedDate` is collected here (that's decided later, at whatever
  /// point the tenant chooses to propose an inspection date — see
  /// `proposeInspection`), and there's no landlord pre-approval gate
  /// before money moves. The booking row is created PENDING and the
  /// charge is kicked off in the same call; if the charge itself fails to
  /// even initialize (e.g. Paystack unreachable), the row still exists so
  /// the tenant can retry via `POST /bookings/:id/pay` later from their
  /// history instead of losing the attempt.
  async create(tenantId: string, dto: CreateBookingDto) {
    const property = await this.prisma.property.findUnique({ where: { id: dto.propertyId } });
    if (!property) throw new NotFoundException('Property not found');

    const isShortlet = property.category === PropertyCategory.SHORTLET;
    if (isShortlet && (!dto.nights || !dto.requestedDate)) {
      throw new BadRequestException('requestedDate and nights are required when booking a Shortlet');
    }

    const booking = await this.prisma.booking.create({
      data: {
        propertyId: dto.propertyId,
        tenantId,
        requestedDate: isShortlet ? new Date(dto.requestedDate!) : undefined,
        nights: isShortlet ? dto.nights : undefined,
        message: dto.message,
      },
      include: { property: true },
    });

    if (isShortlet) {
      return booking;
    }

    const charge = await this.payments.initiateBookingCharge(booking.id, tenantId);
    return { ...booking, ...charge };
  }

  findForTenant(tenantId: string) {
    return this.prisma.booking.findMany({
      where: { tenantId },
      include: { property: true, tenancyAgreement: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  /// Every pending/resolved booking across every property this landlord
  /// owns — the data behind the Bookings tab's "Upcoming Bookings" card
  /// and its "See all" history view. The tenant fields beyond
  /// name/email (photo, gender, occupation, marital status, date of
  /// birth — the client derives age from this) back the landlord-facing
  /// "View Tenant Profile" screen; a landlord only ever sees these for a
  /// tenant who has actually booked one of their properties, never an
  /// arbitrary lookup.
  ///
  /// [lastPaidAt] is derived here (not a raw column) from the most recent
  /// successfully-charged Payment, since a landlord previously had no way
  /// to see when a tenant actually paid at all — unlike [findForTenant],
  /// this used to leave the `payments` relation out entirely.
  async findForLandlord(landlordId: string) {
    const bookings = await this.prisma.booking.findMany({
      where: { property: { landlordId } },
      include: {
        property: true,
        tenant: {
          select: {
            id: true,
            fullName: true,
            email: true,
            profilePhotoUrl: true,
            gender: true,
            occupation: true,
            maritalStatus: true,
            dateOfBirth: true,
          },
        },
        payments: {
          where: { status: { in: ['PAID_HELD', 'RELEASED'] } },
          orderBy: { paidAt: 'desc' },
          take: 1,
          select: { paidAt: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    });
    return bookings.map(({ payments, ...booking }) => ({ ...booking, lastPaidAt: payments[0]?.paidAt ?? null }));
  }

  /// Shortlet-only now — a non-Shortlet booking is charged immediately on
  /// creation (see `create`) and never sits PENDING waiting on this
  /// endpoint; its equivalent landlord decision points are
  /// `respondToInspection` (a specific date) and `rejectBooking` (the
  /// booking outright), both reachable only after payment.
  async respond(id: string, landlordId: string, accepted: boolean) {
    const booking = await this.prisma.booking.findUnique({ where: { id }, include: { property: true } });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.property.landlordId !== landlordId) {
      throw new ForbiddenException('You do not own the property this booking is for');
    }
    if (booking.property.category !== PropertyCategory.SHORTLET) {
      throw new BadRequestException('This booking does not need approval before payment');
    }
    if (booking.status !== BookingStatus.PENDING) {
      throw new BadRequestException('This booking has already been responded to');
    }

    if (accepted) {
      if (!booking.requestedDate || !booking.nights) {
        throw new BadRequestException('This booking is missing its requested dates');
      }
      const newStart = booking.requestedDate;
      const newEnd = addDays(newStart, booking.nights);
      // Don't double-book: reject the accept if another PAID Shortlet stay
      // on this same property already overlaps the requested range. Date
      // conflicts beyond this exact check are explicitly out of scope.
      const conflict = await this.prisma.booking.findFirst({
        where: {
          propertyId: booking.propertyId,
          id: { not: booking.id },
          status: BookingStatus.PAID,
          leaseStartDate: { lt: newEnd },
          leaseEndDate: { gt: newStart },
        },
      });
      if (conflict) {
        throw new BadRequestException('This property is already booked for an overlapping date range');
      }
    }

    const updated = await this.prisma.booking.update({
      where: { id },
      data: { status: accepted ? BookingStatus.ACCEPTED : BookingStatus.DECLINED },
    });
    await this.notifications.create(
      booking.tenantId,
      NotificationType.BOOKING_STATUS,
      accepted ? 'Booking accepted' : 'Booking declined',
      accepted
        ? `Your booking request for ${booking.property.title} was accepted. You can now pay to secure it.`
        : `Your booking request for ${booking.property.title} was declined.`,
    );
    return updated;
  }

  /// `POST /bookings/:id/pay` — starts (or retries) the Paystack charge;
  /// the actual status/lease-date transitions happen later, when the
  /// webhook confirms the charge (see PaymentsService.handleChargeSuccess).
  /// For a non-Shortlet booking this is also called internally by
  /// `create`, so this endpoint mainly exists for a retry — e.g. the
  /// tenant closed the app before finishing checkout the first time.
  pay(id: string, tenantId: string) {
    return this.payments.initiateBookingCharge(id, tenantId);
  }

  /// `POST /bookings/:id/inspection` — tenant proposes (or re-proposes,
  /// after a decline) an inspection date. Valid any time the booking is
  /// PAID_AWAITING_INSPECTION — including much later, from the tenant's
  /// own history, if they chose "book later" right after paying.
  async proposeInspection(id: string, tenantId: string, dto: ProposeInspectionDto) {
    const booking = await this.prisma.booking.findUnique({ where: { id }, include: { property: true } });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.tenantId !== tenantId) throw new ForbiddenException('Not your booking');
    if (booking.property.category === PropertyCategory.SHORTLET) {
      throw new BadRequestException('Shortlet stays have no inspection step');
    }
    if (booking.status !== BookingStatus.PAID_AWAITING_INSPECTION) {
      throw new BadRequestException('This booking is not awaiting an inspection date right now');
    }

    const updated = await this.prisma.booking.update({
      where: { id },
      data: { requestedDate: new Date(dto.requestedDate), status: BookingStatus.INSPECTION_PROPOSED },
    });
    await this.notifications.create(
      booking.property.landlordId,
      NotificationType.BOOKING_STATUS,
      'Inspection date proposed',
      `A tenant proposed an inspection date for ${booking.property.title}.`,
    );
    return updated;
  }

  /// `PATCH /bookings/:id/inspection/respond` — landlord accepts or
  /// declines the tenant's proposed date specifically (not the booking
  /// itself — see `rejectBooking` for the separate outright-rejection
  /// lever). A decline just goes back to PAID_AWAITING_INSPECTION so the
  /// tenant can propose another date, defer, or refund.
  async respondToInspection(id: string, landlordId: string, accepted: boolean) {
    const booking = await this.prisma.booking.findUnique({ where: { id }, include: { property: true } });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.property.landlordId !== landlordId) {
      throw new ForbiddenException('You do not own the property this booking is for');
    }
    if (booking.status !== BookingStatus.INSPECTION_PROPOSED) {
      throw new BadRequestException('This booking has no pending inspection date to respond to');
    }

    const updated = await this.prisma.booking.update({
      where: { id },
      data: accepted
        ? { status: BookingStatus.INSPECTION_CONFIRMED, inspectionConfirmedAt: new Date() }
        : { status: BookingStatus.PAID_AWAITING_INSPECTION, requestedDate: null },
    });
    await this.notifications.create(
      booking.tenantId,
      NotificationType.BOOKING_STATUS,
      accepted ? 'Inspection date confirmed' : 'Inspection date declined',
      accepted
        ? `Your inspection date for ${booking.property.title} was confirmed.`
        : `Your proposed inspection date for ${booking.property.title} was declined — propose another date whenever you're ready, from your bookings.`,
    );
    return updated;
  }

  /// `POST /bookings/:id/reject` — the landlord's distinct "reject this
  /// booking outright" lever (separate from declining just an inspection
  /// date) — full refund, no platform fee withheld, unlike the tenant's
  /// own `refund` action which keeps HomeServant's 0.2% cut.
  rejectBooking(id: string, landlordId: string) {
    return this.payments.rejectBookingByLandlord(id, landlordId);
  }

  /// `POST /bookings/:id/moved-in` — releases the landlord's share and
  /// generates the persisted TenancyAgreement.
  confirmMovedIn(id: string, tenantId: string) {
    return this.payments.releaseBookingOnMovedIn(id, tenantId);
  }

  /// `POST /bookings/:id/refund` — tenant-initiated pre-move-in refund,
  /// minus HomeServant's 0.2% cut.
  refund(id: string, tenantId: string) {
    return this.payments.refundBookingBeforeMoveIn(id, tenantId);
  }

  /// `POST /bookings/:id/renew` — charges again for another lease term;
  /// releases instantly (no hold) once the webhook confirms it.
  renew(id: string, tenantId: string) {
    return this.payments.renewBooking(id, tenantId);
  }
}
