import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BookingStatus, NotificationType, PropertyCategory, VerificationStatus, PaymentPlan } from '@prisma/client';
import { ChatService } from '../chat/chat.service';
import { PlatformSettingsService } from '../platform-settings/platform-settings.service';
import { NotificationsService } from '../notifications/notifications.service';
import { assertRentalAvailable } from '../common/rental-availability';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';
import { CreateBookingDto } from './dto/create-booking.dto';
import { ProposeInspectionDto } from './dto/propose-inspection.dto';

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

/// Booking stages that mean the tenant has paid (and not been refunded).
const PAID_STATUSES = new Set<BookingStatus>([
  BookingStatus.PAID,
  BookingStatus.PAID_AWAITING_INSPECTION,
  BookingStatus.INSPECTION_PROPOSED,
  BookingStatus.INSPECTION_CONFIRMED,
  BookingStatus.MOVED_IN,
]);

@Injectable()
export class BookingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly payments: PaymentsService,
    private readonly platform: PlatformSettingsService,
    private readonly chat: ChatService,
  ) {}

  /// Posts an automatic note about this booking into the tenant–landlord
  /// chat (started if they haven't chatted yet), so both see inspection
  /// updates where they talk. Best-effort: a failure here never undoes the
  /// booking change itself.
  private async noteInChat(booking: { tenantId: string; propertyId: string; property: { landlordId: string } }, body: string) {
    try {
      await this.chat.postBookingSystemMessage({
        tenantId: booking.tenantId,
        landlordId: booking.property.landlordId,
        propertyId: booking.propertyId,
        body,
        createIfMissing: true,
      });
    } catch {
      // Nothing to do: the notification still reaches them.
    }
  }

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
    const property = await this.prisma.property.findUnique({
      where: { id: dto.propertyId },
      include: { landlord: { select: { bannedAt: true, identityVerification: { select: { status: true } } } } },
    });
    if (!property) throw new NotFoundException('Property not found');
    if (property.landlord.bannedAt) throw new ForbiddenException("This listing isn't available any more");
    // Platform Controls: unverified landlords' listings are hidden from
    // browsing, and a direct link can't be used to book one either.
    if (
      property.landlord.identityVerification?.status !== VerificationStatus.APPROVED &&
      (await this.platform.requireVerifiedLandlords())
    ) {
      throw new ForbiddenException("This landlord hasn't been verified yet, so this property can't be booked right now");
    }

    if (property.hiddenByLandlordAt) {
      throw new ForbiddenException("The landlord has hidden this listing for now, so it can't be booked");
    }

    const isShortlet = property.category === PropertyCategory.SHORTLET;
    if (isShortlet && (!dto.nights || !dto.requestedDate)) {
      throw new BadRequestException('requestedDate and nights are required when booking a Shortlet');
    }
    const monthly = dto.paymentPlan === PaymentPlan.MONTHLY;
    if (monthly && (isShortlet || !property.allowMonthlyPayment)) {
      throw new BadRequestException("The landlord doesn't allow monthly payments for this property");
    }

    const planFields = monthly
      ? // Monthly: a month's rent is a twelfth of the yearly price, rounded up.
        { paymentPlan: PaymentPlan.MONTHLY, monthlyRent: Math.ceil(property.price / 12) }
      : { paymentPlan: PaymentPlan.FULL, monthlyRent: null };

    // One live booking per tenant per property. Rent Now used to create a
    // fresh booking every time it was pressed, so a tenant who had already
    // paid could pay again, and History showed the property twice (the
    // extra copy stuck on "Pending").
    const existing = await this.prisma.booking.findMany({
      where: { tenantId, propertyId: dto.propertyId, status: { notIn: [BookingStatus.DECLINED, BookingStatus.REFUNDED] } },
      orderBy: { createdAt: 'desc' },
    });
    const now = Date.now();
    const live = existing.filter(
      (b) =>
        !((b.status === BookingStatus.MOVED_IN || b.status === BookingStatus.PAID) && b.leaseEndDate && b.leaseEndDate.getTime() <= now),
    );
    if (isShortlet) {
      if (live.some((b) => b.status === BookingStatus.PENDING || b.status === BookingStatus.ACCEPTED)) {
        throw new BadRequestException('You already have a booking request for this property — see your Booking History.');
      }
    } else {
      if (live.some((b) => b.status === BookingStatus.MOVED_IN)) {
        throw new BadRequestException("You're already renting this property — see your Booking History.");
      }
      if (live.some((b) => PAID_STATUSES.has(b.status))) {
        throw new BadRequestException("You've already paid for this property — see your Booking History.");
      }
      // Taken by someone else: refuse before creating a booking row.
      await assertRentalAvailable(this.prisma, dto.propertyId, tenantId);
      // An unfinished checkout (Rent Now pressed, never paid): carry on with
      // it instead of starting another booking. If it was actually paid and
      // the webhook just hasn't landed, the charge call confirms it and
      // refuses to charge again.
      const unfinished = live.find((b) => b.status === BookingStatus.PENDING);
      if (unfinished) {
        const reused = await this.prisma.booking.update({
          where: { id: unfinished.id },
          data: { message: dto.message ?? unfinished.message, ...planFields },
          include: { property: true },
        });
        const charge = await this.payments.initiateBookingCharge(reused.id, tenantId);
        return { ...reused, ...charge };
      }
    }

    const booking = await this.prisma.booking.create({
      data: {
        propertyId: dto.propertyId,
        tenantId,
        requestedDate: isShortlet ? new Date(dto.requestedDate!) : undefined,
        nights: isShortlet ? dto.nights : undefined,
        message: dto.message,
        ...(monthly ? planFields : {}),
      },
      include: { property: true },
    });

    // Without this, a landlord's Bookings tab only ever picked up a brand
    // new request on next app restart (AppState fetches it once, at
    // login) — every *subsequent* status change already notifies (see
    // `respond`/`proposeInspection`/`respondToInspection` below and
    // PaymentsService), but creation itself never did, so this was the
    // one gap in that chain. NotificationsService.create is also what
    // pushes the `notification:new` socket event the Flutter client
    // reuses to refetch the bookings list live.
    //
    // Only a Shortlet request is announced here. A normal rental is still
    // unpaid at this point (the tenant may never finish checkout), so the
    // landlord hears about it from PaymentsService ("Tenant paid") once
    // the charge actually clears.
    if (isShortlet) {
      await this.notifications.create(
        property.landlordId,
        NotificationType.BOOKING_STATUS,
        'New booking request',
        `A tenant requested to book ${property.title}.`,
      );
      return booking;
    }

    const charge = await this.payments.initiateBookingCharge(booking.id, tenantId);
    return { ...booking, ...charge };
  }

  async findForTenant(tenantId: string) {
    const [bookings, requireVerified] = await Promise.all([
      this.prisma.booking.findMany({
        where: { tenantId },
        include: {
          property: { include: PlatformSettingsService.landlordStatusInclude },
          tenancyAgreement: true,
          payments: { where: { status: 'REFUNDED' }, select: { refundedById: true }, take: 1 },
          _count: { select: { payments: { where: { status: 'RELEASED' } } } },
        },
        orderBy: { createdAt: 'desc' },
      }),
      this.platform.requireVerifiedLandlords(),
    ]);
    // An unpaid non-Shortlet booking is just an unfinished checkout. Older
    // app versions created a new one on every Rent Now tap, so drop any
    // that's shadowed by another booking for the same property (a paid
    // one, or a newer attempt) — otherwise History shows it twice.
    const shown = bookings.filter(
      (b) =>
        b.status !== BookingStatus.PENDING ||
        b.property.category === PropertyCategory.SHORTLET ||
        !bookings.some(
          (other) =>
            other.id !== b.id &&
            other.propertyId === b.propertyId &&
            (PAID_STATUSES.has(other.status) || other.createdAt > b.createdAt),
        ),
    );
    // Flags let History explain a booked listing that Platform Controls now
    // hides from browsing; the booking itself carries on unaffected.
    return shown.map(({ property: { landlord, ...property }, payments, _count, ...booking }) => ({
      ...booking,
      // Rating a property is only allowed once the landlord has actually
      // been paid for it (see ReviewsService.upsert).
      landlordPaid: _count.payments > 0,
      // An admin refund is always in full (the tenant's own keeps 0.2%).
      refundedByHomeServant: payments.some((p) => !!p.refundedById),
      property: { ...property, ...PlatformSettingsService.listingFlags(landlord.identityVerification?.status, requireVerified) },
    }));
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
  ///
  /// A non-Shortlet booking that is still PENDING is an unfinished
  /// checkout (Rent Now pressed, not paid), not a request the landlord can
  /// act on, so it is left out; it shows up once the tenant pays.
  async findForLandlord(landlordId: string) {
    const bookings = await this.prisma.booking.findMany({
      where: {
        property: { landlordId },
        NOT: { status: BookingStatus.PENDING, property: { category: { not: PropertyCategory.SHORTLET } } },
      },
      include: {
        property: true,
        tenant: {
          select: {
            id: true,
            fullName: true,
            email: true,
            phoneNumber: true,
            profilePhotoUrl: true,
            gender: true,
            occupation: true,
            maritalStatus: true,
            dateOfBirth: true,
            // Their booking profile — read alongside the request.
            bio: true,
            hobbies: true,
            identityVerification: { select: { status: true } },
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
    // The tenant's phone number is only shared once they've paid for this
    // property, so a landlord can't take an unpaid request off-platform
    // (the same line messaging draws, see ChatService).
    const paidTenantIds = new Set(
      bookings.filter((b) => PAID_STATUSES.has(b.status)).map((b) => `${b.tenantId}:${b.propertyId}`),
    );
    return bookings.map(({ payments, ...booking }) => ({
      ...booking,
      tenant: {
        ...booking.tenant,
        phoneNumber: paidTenantIds.has(`${booking.tenantId}:${booking.propertyId}`) ? booking.tenant.phoneNumber : null,
      },
      lastPaidAt: payments[0]?.paidAt ?? null,
    }));
  }

  /// Clears (or, for Undo, restores) booking requests from the landlord's
  /// dashboard feed. Only the landlord's own bookings are touched; nothing
  /// is declined. No ids = every current pending request. Returns how many
  /// changed.
  async setFeedCleared(landlordId: string, cleared: boolean, bookingIds?: string[]): Promise<{ count: number }> {
    const { count } = await this.prisma.booking.updateMany({
      where: {
        property: { landlordId },
        ...(bookingIds?.length
          ? { id: { in: bookingIds } }
          : { status: BookingStatus.PENDING, property: { landlordId, category: PropertyCategory.SHORTLET } }),
      },
      data: { landlordFeedClearedAt: cleared ? new Date() : null },
    });
    return { count };
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

  confirmPayment(reference: string, tenantId: string) {
    return this.payments.confirmBookingCharge(reference, tenantId);
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
    // Also while a proposed date is still waiting on the landlord, so the
    // tenant can change it.
    if (booking.status !== BookingStatus.PAID_AWAITING_INSPECTION && booking.status !== BookingStatus.INSPECTION_PROPOSED) {
      throw new BadRequestException('This booking is not awaiting an inspection date right now');
    }

    const date = inspectionDate(dto.requestedDate);
    const updated = await this.prisma.booking.update({
      where: { id },
      data: { requestedDate: date, status: BookingStatus.INSPECTION_PROPOSED },
    });
    await this.notifications.create(
      booking.property.landlordId,
      NotificationType.BOOKING_STATUS,
      'Inspection date proposed',
      `A tenant proposed ${formatInspectionDate(date)} to inspect ${booking.property.title}.`,
    );
    await this.noteInChat(
      booking,
      `Inspection date proposed for ${booking.property.title}: ${formatInspectionDate(date)}. The landlord can confirm it or pick another date.`,
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
    const when = booking.requestedDate ? formatInspectionDate(booking.requestedDate) : 'the proposed date';
    await this.notifications.create(
      booking.tenantId,
      NotificationType.BOOKING_STATUS,
      accepted ? 'Inspection date confirmed' : 'Inspection date declined',
      accepted
        ? `Your inspection of ${booking.property.title} on ${when} was confirmed.`
        : `Your proposed inspection date for ${booking.property.title} was declined — propose another date whenever you're ready, from your booking history.`,
    );
    await this.noteInChat(
      booking,
      accepted
        ? `The landlord confirmed the inspection of ${booking.property.title} on ${when}.`
        : `The landlord declined ${when} for inspecting ${booking.property.title}. The tenant can propose another date, or the landlord can set one.`,
    );
    return updated;
  }

  /// `POST /bookings/:id/inspection/schedule` — the landlord sets the
  /// inspection date themselves: when the tenant hasn't proposed one yet,
  /// or instead of the date they proposed. Confirms it straight away.
  async scheduleInspection(id: string, landlordId: string, dto: ProposeInspectionDto) {
    const booking = await this.prisma.booking.findUnique({ where: { id }, include: { property: true } });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.property.landlordId !== landlordId) {
      throw new ForbiddenException('You do not own the property this booking is for');
    }
    if (booking.property.category === PropertyCategory.SHORTLET) {
      throw new BadRequestException('Shortlet stays have no inspection step');
    }
    if (booking.status !== BookingStatus.PAID_AWAITING_INSPECTION && booking.status !== BookingStatus.INSPECTION_PROPOSED) {
      throw new BadRequestException('This booking is not waiting on an inspection date');
    }
    const date = inspectionDate(dto.requestedDate);
    const updated = await this.prisma.booking.update({
      where: { id },
      data: { requestedDate: date, status: BookingStatus.INSPECTION_CONFIRMED, inspectionConfirmedAt: new Date() },
    });
    await this.notifications.create(
      booking.tenantId,
      NotificationType.BOOKING_STATUS,
      'Inspection date set',
      `Your landlord set ${formatInspectionDate(date)} to inspect ${booking.property.title}. Message them if that doesn't work for you.`,
    );
    await this.noteInChat(booking, `The landlord set the inspection of ${booking.property.title} for ${formatInspectionDate(date)}.`);
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
  /// See PaymentsService.payMonthlyRent.
  payMonth(bookingId: string, tenantId: string) {
    return this.payments.payMonthlyRent(bookingId, tenantId);
  }

  renew(id: string, tenantId: string, expected?: { amount?: number; leaseMonths?: number }) {
    return this.payments.renewBooking(id, tenantId, expected);
  }

  renewalQuote(id: string, tenantId: string) {
    return this.payments.renewalQuote(id, tenantId);
  }

  /// The app has always called this, but the route was never added, so
  /// tenants saw "isn't ready yet" even after moving in. Someone who isn't
  /// the booking's tenant or landlord gets the same 404 as a missing
  /// agreement, so booking ids can't be probed.
  async tenancyAgreement(bookingId: string, userId: string) {
    const agreement = await this.prisma.tenancyAgreement.findFirst({
      where: {
        bookingId,
        booking: { OR: [{ tenantId: userId }, { property: { landlordId: userId } }] },
      },
    });
    if (!agreement) throw new NotFoundException('No tenancy agreement for this booking yet');
    return agreement;
  }
}

/// An inspection date from the app ("YYYY-MM-DD" or an ISO timestamp),
/// refused if it's before today.
function inspectionDate(value: string): Date {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) throw new BadRequestException('Choose a valid inspection date');
  const startOfToday = new Date();
  startOfToday.setUTCHours(0, 0, 0, 0);
  if (date.getTime() < startOfToday.getTime() - 24 * 60 * 60 * 1000) {
    throw new BadRequestException('Choose an inspection date from today onwards');
  }
  return date;
}

/// "Fri, 2 October 2026", plus " at 10:00 am" when a time was chosen (the
/// in-chat picker asks for one) — in Nigerian time, for notifications and
/// chat notes.
export function formatInspectionDate(date: Date): string {
  const tz = 'Africa/Lagos';
  const day = date.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'long', year: 'numeric', timeZone: tz });
  const time = date.toLocaleTimeString('en-GB', { hour: 'numeric', minute: '2-digit', hour12: true, timeZone: tz });
  return /^12:00\s?am$/i.test(time) ? day : `${day} at ${time.toLowerCase()}`;
}
