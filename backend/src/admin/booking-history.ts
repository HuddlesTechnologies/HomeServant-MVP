import { BookingStatus, PaymentStatus, Prisma } from '@prisma/client';

/// What the admin console loads for each of a tenant's bookings: the
/// booking itself, every detail and image of the property, and each
/// payment made for it (a renewal charges again, so there can be several).
export const adminBookingHistorySelect = {
  id: true,
  propertyId: true,
  status: true,
  requestedDate: true,
  inspectionConfirmedAt: true,
  nights: true,
  priceSnapshot: true,
  priceUnitSnapshot: true,
  leaseStartDate: true,
  leaseEndDate: true,
  message: true,
  paymentPlan: true,
  monthlyRent: true,
  rentPaidThrough: true,
  createdAt: true,
  updatedAt: true,
  property: {
    select: {
      id: true,
      listingNumber: true,
      title: true,
      location: true,
      state: true,
      category: true,
      price: true,
      priceUnit: true,
      bedrooms: true,
      bathrooms: true,
      description: true,
      imageUrl: true,
      galleryUrls: true,
      unitAddress: true,
      roomNumber: true,
      rentDurationMonths: true,
      isOccupied: true,
      landlord: { select: { id: true, fullName: true, email: true, phoneNumber: true } },
    },
  },
  payments: {
    orderBy: { createdAt: 'asc' },
    select: {
      id: true,
      amount: true,
      platformFeeAmount: true,
      status: true,
      paystackReference: true,
      paidAt: true,
      releasedAt: true,
      refundedAt: true,
      refundRequestedBy: true,
      refundRequestedAmount: true,
      refundLastAttemptAt: true,
      refundLastError: true,
      refundReason: true,
      heldForVerificationAt: true,
      createdAt: true,
      updatedAt: true,
    },
  },
} satisfies Prisma.BookingSelect;

type HistoryBooking = Prisma.BookingGetPayload<{ select: typeof adminBookingHistorySelect }>;
type HistoryPayment = HistoryBooking['payments'][number];

/// success: it went through; pending: waiting on someone; warning: a
/// refund or other reversal; danger: something failed.
export type HistoryTone = 'success' | 'pending' | 'warning' | 'danger' | 'info';

export interface BookingTimelineEvent {
  at: Date;
  label: string;
  tone: HistoryTone;
  detail?: string;
}

const WHO_REFUNDED: Record<string, string> = {
  TENANT: 'the tenant asked for it',
  LANDLORD: 'the landlord refunded them',
  ADMIN: 'HomeServant refunded them',
};

function naira(kobo: number): string {
  return `₦${Math.round(kobo / 100).toLocaleString('en-NG')}`;
}

/// The one-line outcome shown on a booking in the admin console: whether
/// it succeeded, is still pending, failed, or was refunded (and who
/// started the refund).
export function bookingOutcome(
  booking: Pick<HistoryBooking, 'status'> &
    Partial<Pick<HistoryBooking, 'paymentPlan' | 'rentPaidThrough' | 'leaseEndDate'>> & { payments: HistoryPayment[] },
): {
  label: string;
  tone: HistoryTone;
} {
  const latest = booking.payments[booking.payments.length - 1];
  const refunded = booking.payments.find((p) => p.status === PaymentStatus.REFUNDED);
  switch (booking.status) {
    case BookingStatus.REFUNDED: {
      const by = refunded?.refundRequestedBy;
      if (by === 'TENANT') return { label: 'Refunded (tenant asked)', tone: 'warning' };
      if (by === 'ADMIN') return { label: 'Refunded by HomeServant', tone: 'warning' };
      return { label: 'Refunded by landlord', tone: 'warning' };
    }
    case BookingStatus.DECLINED:
      return { label: refunded ? 'Declined by landlord · refunded' : 'Declined by landlord', tone: 'warning' };
    case BookingStatus.MOVED_IN:
    case BookingStatus.PAID: {
      const monthlyOverdue =
        booking.paymentPlan === 'MONTHLY' &&
        !!booking.rentPaidThrough &&
        !!booking.leaseEndDate &&
        booking.rentPaidThrough < booking.leaseEndDate &&
        booking.rentPaidThrough.getTime() < Date.now();
      if (monthlyOverdue) return { label: 'Successful · monthly rent overdue', tone: 'danger' };
      return { label: booking.paymentPlan === 'MONTHLY' ? 'Successful · paying monthly' : 'Successful', tone: 'success' };
    }
  }
  if (latest?.status === PaymentStatus.PAID_HELD && latest.refundLastAttemptAt) {
    return latest.refundLastError
      ? { label: 'Refund failed', tone: 'danger' }
      : { label: 'Refund requested', tone: 'pending' };
  }
  if (latest?.status === PaymentStatus.FAILED) return { label: 'Payment failed', tone: 'danger' };
  if (!latest || latest.status === PaymentStatus.INITIATED) return { label: 'Pending payment', tone: 'pending' };
  switch (booking.status) {
    case BookingStatus.INSPECTION_PROPOSED:
      return { label: 'Pending · inspection date proposed', tone: 'pending' };
    case BookingStatus.INSPECTION_CONFIRMED:
      return { label: 'Pending · inspection confirmed', tone: 'pending' };
    default:
      return { label: 'Pending · paid, awaiting move-in', tone: 'pending' };
  }
}

/// Every dated event on a booking, oldest first: requested, each payment
/// started/succeeded/failed, inspection, move-in, payout, refund asked/
/// failed/done, and the lease end.
export function bookingTimeline(booking: HistoryBooking): BookingTimelineEvent[] {
  const events: BookingTimelineEvent[] = [
    { at: booking.createdAt, label: 'Booking requested', tone: 'info', detail: booking.message ?? undefined },
  ];
  booking.payments.forEach((payment, index) => {
    const monthly = booking.paymentPlan === 'MONTHLY';
    const which = monthly
      ? index === 0
        ? ' (first month)'
        : ' (monthly rent)'
      : booking.payments.length > 1
        ? index === 0
          ? ' (first payment)'
          : ' (renewal)'
        : '';
    events.push({ at: payment.createdAt, label: `Payment started${which}`, tone: 'info', detail: naira(payment.amount) });
    if (payment.status === PaymentStatus.FAILED) {
      events.push({ at: payment.updatedAt, label: `Payment failed${which}`, tone: 'danger', detail: naira(payment.amount) });
    }
    if (payment.paidAt) {
      events.push({
        at: payment.paidAt,
        label: `Payment successful${which}`,
        tone: 'success',
        detail: `${naira(payment.amount)} held by HomeServant · ref ${payment.paystackReference}`,
      });
    }
    if (payment.heldForVerificationAt) {
      events.push({
        at: payment.heldForVerificationAt,
        label: 'Payout held until the landlord is verified',
        tone: 'pending',
      });
    }
    if (payment.releasedAt) {
      events.push({
        at: payment.releasedAt,
        label: 'Paid out to the landlord',
        tone: 'success',
        detail: `${naira(payment.amount - payment.platformFeeAmount)} after ${naira(payment.platformFeeAmount)} fee`,
      });
    }
    if (payment.refundLastAttemptAt) {
      const who = payment.refundRequestedBy ? WHO_REFUNDED[payment.refundRequestedBy] : undefined;
      events.push({
        at: payment.refundLastAttemptAt,
        label: payment.refundLastError && payment.status !== PaymentStatus.REFUNDED ? 'Refund failed' : 'Refund requested',
        tone: payment.refundLastError && payment.status !== PaymentStatus.REFUNDED ? 'danger' : 'pending',
        detail: [
          who,
          payment.refundRequestedAmount != null ? naira(payment.refundRequestedAmount) : undefined,
          payment.status !== PaymentStatus.REFUNDED ? payment.refundLastError ?? undefined : undefined,
        ]
          .filter(Boolean)
          .join(' · ') || undefined,
      });
    }
    if (payment.refundedAt) {
      events.push({
        at: payment.refundedAt,
        label: 'Refunded',
        tone: 'warning',
        detail: payment.refundReason ?? (payment.refundRequestedBy ? WHO_REFUNDED[payment.refundRequestedBy] : undefined),
      });
    }
  });
  if (booking.inspectionConfirmedAt) {
    events.push({ at: booking.inspectionConfirmedAt, label: 'Landlord confirmed the inspection date', tone: 'success' });
  }
  if (booking.status === BookingStatus.DECLINED) {
    events.push({ at: booking.updatedAt, label: 'Landlord declined the booking', tone: 'warning' });
  }
  if (booking.leaseStartDate) {
    events.push({
      at: booking.leaseStartDate,
      label: booking.nights ? 'Stay started' : 'Moved in · lease started',
      tone: 'success',
    });
  }
  if (booking.leaseEndDate) {
    const ended = booking.leaseEndDate.getTime() <= Date.now();
    events.push({
      at: booking.leaseEndDate,
      label: booking.nights ? (ended ? 'Stay ended' : 'Stay ends') : ended ? 'Lease ended' : 'Lease ends',
      tone: 'info',
    });
  }
  return events.sort((a, b) => a.at.getTime() - b.at.getTime());
}

/// The admin console's shape for one booking in a tenant's history.
export function toAdminBookingHistory(booking: HistoryBooking) {
  const outcome = bookingOutcome(booking);
  const property = booking.property;
  const images = [property.imageUrl, ...property.galleryUrls].filter(
    (url, index, all): url is string => !!url && all.indexOf(url) === index,
  );
  return {
    id: booking.id,
    propertyId: booking.propertyId,
    // Kept for older console builds.
    propertyTitle: property.title,
    price: booking.priceSnapshot ?? property.price,
    priceUnit: booking.priceUnitSnapshot ?? property.priceUnit,
    status: booking.status,
    outcome: outcome.label,
    outcomeTone: outcome.tone,
    requestedDate: booking.requestedDate,
    nights: booking.nights,
    paymentPlan: booking.paymentPlan,
    monthlyRent: booking.monthlyRent,
    rentPaidThrough: booking.rentPaidThrough,
    leaseStartDate: booking.leaseStartDate,
    leaseEndDate: booking.leaseEndDate,
    createdAt: booking.createdAt,
    updatedAt: booking.updatedAt,
    property: {
      id: property.id,
      listingNumber: property.listingNumber,
      title: property.title,
      location: property.location,
      state: property.state,
      category: property.category,
      price: property.price,
      priceUnit: property.priceUnit,
      bedrooms: property.bedrooms,
      bathrooms: property.bathrooms,
      description: property.description,
      unitAddress: property.unitAddress,
      roomNumber: property.roomNumber,
      rentDurationMonths: property.rentDurationMonths,
      isOccupied: property.isOccupied,
      images,
      landlord: property.landlord,
    },
    payments: booking.payments.map((p) => ({
      id: p.id,
      amount: p.amount,
      platformFeeAmount: p.platformFeeAmount,
      status: p.status,
      reference: p.paystackReference,
      paidAt: p.paidAt,
      releasedAt: p.releasedAt,
      refundedAt: p.refundedAt,
      refundRequestedBy: p.refundRequestedBy,
      refundLastError: p.refundLastError,
      createdAt: p.createdAt,
    })),
    timeline: bookingTimeline(booking),
  };
}
