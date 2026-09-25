import { BadRequestException, ForbiddenException, Injectable, InternalServerErrorException, Logger, NotFoundException } from '@nestjs/common';
import { randomBytes } from 'crypto';
import { BookingStatus, NotificationType, OrderItemStatus, Payment, PaymentPurpose, PaymentStatus, PriceUnit, PropertyCategory } from '@prisma/client';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';

/// HomeServant's cut on a normal release (marketplace, rental move-in,
/// rental renewal, shortlet instant release) — 5%, expressed in basis
/// points of 10000 to avoid floating point.
const PLATFORM_FEE_BPS = 500;
/// The cut withheld specifically on a rental refund issued *before*
/// move-in — 0.2%, not the normal 5%. Paystack's own processing fee is
/// simply never returned to the merchant on a refund by default, so the
/// tenant ends up bearing both cuts automatically without this app having
/// to compute Paystack's own fee.
const REFUND_FEE_BPS = 20;
const BPS_DENOMINATOR = 10000;

/// A rental renewal can only be requested once the current lease is
/// within this many days of its leaseEndDate (or already past it, as long
/// as the lease-lifecycle cron hasn't already auto-expired/relisted the
/// property — see renewBooking).
const RENEWAL_WINDOW_DAYS = 30;

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/// Every non-Shortlet rental status between payment and move-in — the
/// tenant can refund (refundBookingBeforeMoveIn) or the landlord can
/// reject outright (rejectBookingByLandlord) from any of these.
const PRE_MOVE_IN_STATUSES: BookingStatus[] = [
  BookingStatus.PAID_AWAITING_INSPECTION,
  BookingStatus.INSPECTION_PROPOSED,
  BookingStatus.INSPECTION_CONFIRMED,
];

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * MS_PER_DAY);
}

function addMonths(date: Date, months: number): Date {
  const d = new Date(date);
  d.setMonth(d.getMonth() + months);
  return d;
}

/// Every kobo/naira placeholder below is Paystack's smallest-unit
/// convention: Property.price/Product.price/etc are stored in whole Naira
/// throughout this codebase (matches the "₦" labels in the Flutter admin/
/// listing screens), so every amount is multiplied by 100 once, right
/// here, before it's ever handed to Paystack — nowhere else in this
/// service deals in Naira.
const KOBO_PER_NAIRA = 100;

/// The single home for HomeServant's escrow logic: charge in full, hold
/// in HomeServant's own Paystack balance, and later Transfer the
/// recipient's 95% share (HomeServant keeps 5%) — never Paystack Split
/// Payments. Used by both BookingsService (rentals/shortlets) and
/// MarketplaceOrdersService (order items), so every money-movement rule
/// lives in one place instead of being re-derived per feature.
@Injectable()
export class PaymentsService {
  private readonly logger = new Logger('Payments');

  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
  ) {}

  // ---------------------------------------------------------------------
  // Marketplace order items
  // ---------------------------------------------------------------------

  /// Called right after MarketplaceOrdersService.create commits the order
  /// + its items — one Paystack transaction per item (Payment.orderItemId
  /// is unique, so a multi-item/multi-vendor order is necessarily one
  /// charge per item, never one combined charge). A per-item failure to
  /// reach Paystack doesn't fail the whole order (it already exists); that
  /// item just comes back with `error` set so the buyer can retry it.
  async initiateOrderItemCharges(
    items: { id: string; productName: string; unitPrice: number; quantity: number; vendorId: string; vendorUserId: string }[],
    buyerId: string,
    buyerEmail: string,
  ): Promise<{ itemId: string; reference: string; authorizationUrl: string | null; error?: string }[]> {
    const results: { itemId: string; reference: string; authorizationUrl: string | null; error?: string }[] = [];
    for (const item of items) {
      const amountNaira = item.unitPrice * item.quantity;
      const amountKobo = amountNaira * KOBO_PER_NAIRA;
      const platformFeeKobo = this.fee(amountKobo, PLATFORM_FEE_BPS);
      const reference = this.generateReference('mkt');

      await this.prisma.payment.create({
        data: {
          purpose: PaymentPurpose.MARKETPLACE_ORDER_ITEM,
          orderItemId: item.id,
          payerId: buyerId,
          recipientUserId: item.vendorUserId,
          amount: amountKobo,
          platformFeeAmount: platformFeeKobo,
          paystackReference: reference,
          status: PaymentStatus.INITIATED,
        },
      });

      try {
        const init = await this.paystack.initializeTransaction(buyerEmail, amountKobo, reference, {
          orderItemId: item.id,
          purpose: 'MARKETPLACE_ORDER_ITEM',
        });
        results.push({ itemId: item.id, reference: init.reference, authorizationUrl: init.authorizationUrl });
      } catch (err) {
        this.logger.error(`Could not initialize Paystack transaction for order item ${item.id}: ${(err as Error).message}`);
        await this.prisma.payment.update({ where: { orderItemId: item.id }, data: { status: PaymentStatus.FAILED } });
        results.push({ itemId: item.id, reference, authorizationUrl: null, error: 'Could not start payment for this item — try again' });
      }
    }
    return results;
  }

  /// `POST /marketplace-orders/items/:id/confirm-received` — buyer-only,
  /// must own the order. Releases the vendor's 95% share and marks the
  /// item COMPLETED. This is the *only* path that releases a marketplace
  /// escrow payment; see MarketplaceOrdersService.respondToItem for why a
  /// vendor can no longer mark an item COMPLETED directly.
  async confirmOrderItemReceived(itemId: string, buyerId: string) {
    const item = await this.prisma.marketplaceOrderItem.findUnique({
      where: { id: itemId },
      include: { order: { select: { buyerId: true } }, payment: true, vendor: true },
    });
    if (!item) throw new NotFoundException('Order item not found');
    if (item.order.buyerId !== buyerId) throw new ForbiddenException('You do not own this order');
    if (item.status !== OrderItemStatus.PENDING) {
      throw new BadRequestException('This item has already been completed or cancelled');
    }
    if (!item.payment || item.payment.status !== PaymentStatus.PAID_HELD) {
      throw new BadRequestException('Payment for this item is not held yet — nothing to release');
    }

    await this.releasePaymentToRecipient(item.payment, {
      bankCode: item.vendor.bankCode,
      accountNumber: item.vendor.accountNumber,
      accountName: item.vendor.accountName,
      reason: `HomeServant marketplace payout — ${item.productName}`,
    });

    const updated = await this.prisma.marketplaceOrderItem.update({ where: { id: itemId }, data: { status: OrderItemStatus.COMPLETED } });

    await this.notifyBoth(
      item.vendor.userId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Payment released',
      `The buyer confirmed receipt of ${item.productName} — your payout has been sent.`,
    );
    await this.notifyBoth(
      buyerId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Order completed',
      `Thanks for confirming receipt of ${item.productName}.`,
    );

    return updated;
  }

  /// Full refund (no platform fee withheld — the 0.2% cut is specific to
  /// the rental pre-move-in refund path, see refundBookingBeforeMoveIn)
  /// for an order item the vendor cancels while its payment is still
  /// held. A no-op if the item was never actually charged (still
  /// INITIATED/FAILED) — nothing to refund.
  async refundOrderItemIfHeld(itemId: string): Promise<void> {
    const payment = await this.prisma.payment.findUnique({ where: { orderItemId: itemId } });
    if (!payment || payment.status !== PaymentStatus.PAID_HELD) return;
    await this.paystack.refundTransaction(payment.paystackReference);
    await this.prisma.payment.update({
      where: { id: payment.id },
      data: { status: PaymentStatus.REFUNDED, refundedAt: new Date(), platformFeeAmount: 0 },
    });
  }

  /// Auto-release path for MarketplaceAutoReleaseService's 7-day
  /// safety-net cron — same release mechanics as
  /// `confirmOrderItemReceived`, minus the buyer-ownership check, since
  /// there's no acting buyer here; eligibility (item still PENDING,
  /// payment still held, and no open Report against it) is entirely the
  /// caller's responsibility to have already checked. Silently returns if
  /// the item turns out not to be in the expected state — the cron may
  /// have raced with the buyer clicking "received" in the meantime.
  async autoReleaseOrderItem(itemId: string): Promise<void> {
    const item = await this.prisma.marketplaceOrderItem.findUnique({
      where: { id: itemId },
      include: { order: { select: { buyerId: true } }, payment: true, vendor: true },
    });
    if (!item || item.status !== OrderItemStatus.PENDING || !item.payment || item.payment.status !== PaymentStatus.PAID_HELD) {
      return;
    }

    await this.releasePaymentToRecipient(item.payment, {
      bankCode: item.vendor.bankCode,
      accountNumber: item.vendor.accountNumber,
      accountName: item.vendor.accountName,
      reason: `HomeServant marketplace payout (auto-released) — ${item.productName}`,
    });
    await this.prisma.marketplaceOrderItem.update({ where: { id: itemId }, data: { status: OrderItemStatus.COMPLETED } });

    await this.notifyBoth(
      item.vendor.userId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Payment released',
      `Your payout for ${item.productName} was released automatically 7 days after ${item.fulfillment === 'DELIVERY' ? 'shipping' : 'payment'} — the buyer never confirmed receipt.`,
    );
    await this.notifyBoth(
      item.order.buyerId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Order completed',
      `${item.productName} was automatically marked as received 7 days after ${item.fulfillment === 'DELIVERY' ? 'shipping' : 'payment'} since it wasn't confirmed. Contact support if there's a problem.`,
    );
  }

  // ---------------------------------------------------------------------
  // Rental / Shortlet bookings
  // ---------------------------------------------------------------------

  /// `POST /bookings/:id/pay` (also called internally right after
  /// `BookingsService.create` for a non-Shortlet booking) — tenant-only.
  /// A Shortlet booking must be landlord-ACCEPTED first (unchanged flow);
  /// a non-Shortlet booking charges straight from PENDING (no landlord
  /// pre-approval — this is also what makes this endpoint work as a
  /// *retry* if an earlier attempt never completed). Snapshots the
  /// property's current price/unit onto the booking (same convention as
  /// MarketplaceOrderItem's snapshot) and starts a Paystack transaction
  /// for the full amount (a Shortlet's nights are multiplied in here).
  /// Any stale INITIATED Payment from an abandoned earlier attempt is
  /// marked FAILED first — see the idempotency note on
  /// handleChargeSuccess for why this matters.
  async initiateBookingCharge(bookingId: string, tenantId: string) {
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      include: { property: true, tenant: true },
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.tenantId !== tenantId) throw new ForbiddenException('Not your booking');
    const isShortlet = booking.property.category === PropertyCategory.SHORTLET;
    const readyForPayment = isShortlet ? booking.status === BookingStatus.ACCEPTED : booking.status === BookingStatus.PENDING;
    if (!readyForPayment) {
      throw new BadRequestException('This booking is not ready for payment yet');
    }
    if (booking.property.category !== PropertyCategory.SHORTLET && !booking.property.rentDurationMonths) {
      throw new BadRequestException('This property has no rent duration configured — contact the landlord');
    }
    if (booking.property.category === PropertyCategory.SHORTLET && !booking.nights) {
      throw new BadRequestException('This booking is missing its number of nights');
    }

    return this.chargeBooking(booking, booking.tenant.email);
  }

  /// `POST /bookings/:id/renew` — tenant-only, only for an active
  /// (MOVED_IN) non-Shortlet lease, within RENEWAL_WINDOW_DAYS of its
  /// current leaseEndDate. Charges again exactly like the first payment;
  /// what makes this a *renewal* rather than a fresh payment is purely
  /// that the booking is already MOVED_IN when the webhook later sees the
  /// charge succeed (see handleChargeSuccess) — no separate flag needed.
  async renewBooking(bookingId: string, tenantId: string) {
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      include: { property: true, tenant: true },
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.tenantId !== tenantId) throw new ForbiddenException('Not your booking');
    if (booking.status !== BookingStatus.MOVED_IN) {
      throw new BadRequestException('Only an active lease can be renewed');
    }
    if (booking.property.category === PropertyCategory.SHORTLET) {
      throw new BadRequestException('Shortlet bookings cannot be renewed');
    }
    if (!booking.property.rentDurationMonths) {
      throw new BadRequestException('This property has no rent duration configured — contact the landlord');
    }
    if (!booking.leaseEndDate) {
      throw new InternalServerErrorException('This lease is missing its end date');
    }
    if (!booking.property.isOccupied) {
      throw new BadRequestException('This lease has already ended and the unit was relisted — please make a new booking request');
    }
    const daysUntilEnd = (booking.leaseEndDate.getTime() - Date.now()) / MS_PER_DAY;
    if (daysUntilEnd > RENEWAL_WINDOW_DAYS) {
      throw new BadRequestException(`Too early to renew — you can renew starting ${RENEWAL_WINDOW_DAYS} days before your lease ends`);
    }

    return this.chargeBooking(booking, booking.tenant.email);
  }

  private async chargeBooking(
    booking: {
      id: string;
      propertyId: string;
      tenantId: string;
      nights: number | null;
      property: { price: number; priceUnit: PriceUnit; landlordId: string; category: PropertyCategory };
    },
    tenantEmail: string,
  ) {
    await this.prisma.payment.updateMany({
      where: { bookingId: booking.id, status: PaymentStatus.INITIATED },
      data: { status: PaymentStatus.FAILED },
    });

    const priceNaira = booking.property.price;
    const amountNaira = booking.property.category === PropertyCategory.SHORTLET ? priceNaira * (booking.nights ?? 1) : priceNaira;
    const amountKobo = amountNaira * KOBO_PER_NAIRA;
    const platformFeeKobo = this.fee(amountKobo, PLATFORM_FEE_BPS);
    const reference = this.generateReference('rent');

    await this.prisma.$transaction([
      this.prisma.payment.create({
        data: {
          purpose: PaymentPurpose.RENTAL_BOOKING,
          bookingId: booking.id,
          payerId: booking.tenantId,
          recipientUserId: booking.property.landlordId,
          amount: amountKobo,
          platformFeeAmount: platformFeeKobo,
          paystackReference: reference,
          status: PaymentStatus.INITIATED,
        },
      }),
      this.prisma.booking.update({
        where: { id: booking.id },
        data: { priceSnapshot: priceNaira, priceUnitSnapshot: booking.property.priceUnit },
      }),
    ]);

    try {
      const init = await this.paystack.initializeTransaction(tenantEmail, amountKobo, reference, {
        bookingId: booking.id,
        purpose: 'RENTAL_BOOKING',
      });
      return { reference: init.reference, authorizationUrl: init.authorizationUrl };
    } catch (err) {
      await this.prisma.payment.update({ where: { paystackReference: reference }, data: { status: PaymentStatus.FAILED } });
      throw err;
    }
  }

  /// `POST /bookings/:id/moved-in` — tenant-only, only while PAID (i.e.
  /// non-Shortlet, payment held, not yet moved in). Releases the
  /// landlord's 95% share, generates the one persisted TenancyAgreement,
  /// flips Property.isOccupied, and notifies both parties.
  async releaseBookingOnMovedIn(bookingId: string, tenantId: string) {
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      include: { property: true, tenant: true },
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.tenantId !== tenantId) throw new ForbiddenException('Not your booking');
    if (booking.property.category === PropertyCategory.SHORTLET) {
      throw new BadRequestException('Shortlet stays are released automatically — there is no separate move-in step');
    }
    if (booking.status !== BookingStatus.INSPECTION_CONFIRMED) {
      throw new BadRequestException('This booking is not awaiting move-in');
    }
    if (!booking.property.rentDurationMonths) {
      throw new InternalServerErrorException('This property has no rent duration configured');
    }

    const payment = await this.prisma.payment.findFirst({
      where: { bookingId, status: PaymentStatus.PAID_HELD },
      orderBy: { createdAt: 'desc' },
    });
    if (!payment) throw new BadRequestException('No held payment found for this booking');

    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: booking.property.landlordId } });
    await this.releasePaymentToRecipient(payment, {
      bankCode: landlord.bankCode,
      accountNumber: landlord.accountNumber,
      accountName: landlord.accountName,
      reason: `HomeServant rent release — ${booking.property.title}`,
    });

    const leaseStart = new Date();
    const leaseEnd = addMonths(leaseStart, booking.property.rentDurationMonths);

    const [updatedBooking] = await this.prisma.$transaction([
      this.prisma.booking.update({
        where: { id: bookingId },
        data: { status: BookingStatus.MOVED_IN, leaseStartDate: leaseStart, leaseEndDate: leaseEnd },
      }),
      this.prisma.property.update({ where: { id: booking.propertyId }, data: { isOccupied: true } }),
      this.prisma.tenancyAgreement.create({
        data: {
          bookingId,
          propertyTitle: booking.property.title,
          propertyLocation: booking.property.location,
          propertyState: booking.property.state,
          rentAmount: booking.priceSnapshot ?? booking.property.price,
          priceUnit: booking.priceUnitSnapshot ?? booking.property.priceUnit,
          leaseStartDate: leaseStart,
          leaseEndDate: leaseEnd,
          landlordName: landlord.fullName || landlord.email,
          landlordEmail: landlord.email,
          landlordPhone: landlord.phoneNumber,
          tenantName: booking.tenant.fullName || booking.tenant.email,
          tenantEmail: booking.tenant.email,
          tenantPhone: booking.tenant.phoneNumber,
        },
      }),
    ]);

    await this.notifyBoth(
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Welcome home!',
      `You've moved into ${booking.property.title}. Your tenancy agreement is ready in your bookings.`,
    );
    await this.notifyBoth(
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Tenant moved in',
      `Your tenant has moved into ${booking.property.title} and your payout has been released.`,
    );

    return updatedBooking;
  }

  /// `POST /bookings/:id/refund` — tenant-only, tenant-*initiated*, any
  /// time before move-in (paid-awaiting-inspection, inspection proposed,
  /// or inspection confirmed), and only for a non-Shortlet (a Shortlet's
  /// payment is already released instantly on charge success — there's no
  /// held escrow left to refund from by then). Refunds `amount - 0.2%`;
  /// Paystack itself never returns its own processing fee to the merchant
  /// on a refund, so the tenant ends up bearing both cuts automatically.
  /// Contrast with `rejectBookingByLandlord`, the landlord-initiated
  /// equivalent, which refunds in full.
  async refundBookingBeforeMoveIn(bookingId: string, tenantId: string) {
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      include: { property: true, tenant: true },
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.tenantId !== tenantId) throw new ForbiddenException('Not your booking');
    if (booking.property.category === PropertyCategory.SHORTLET) {
      throw new BadRequestException('Shortlet payments release instantly and cannot be refunded through this action');
    }
    if (!PRE_MOVE_IN_STATUSES.includes(booking.status)) {
      throw new BadRequestException('Only a paid booking that hasn’t been moved into yet can be refunded');
    }

    const payment = await this.prisma.payment.findFirst({
      where: { bookingId, status: PaymentStatus.PAID_HELD },
      orderBy: { createdAt: 'desc' },
    });
    if (!payment) throw new BadRequestException('No held payment found for this booking');

    const refundFeeKobo = this.fee(payment.amount, REFUND_FEE_BPS);
    const refundAmountKobo = payment.amount - refundFeeKobo;
    await this.paystack.refundTransaction(payment.paystackReference, refundAmountKobo);

    const [updatedBooking] = await this.prisma.$transaction([
      this.prisma.booking.update({ where: { id: bookingId }, data: { status: BookingStatus.REFUNDED } }),
      this.prisma.payment.update({
        where: { id: payment.id },
        data: { status: PaymentStatus.REFUNDED, refundedAt: new Date(), platformFeeAmount: refundFeeKobo },
      }),
    ]);

    const landlord = await this.prisma.user.findUnique({ where: { id: booking.property.landlordId }, select: { id: true, email: true } });

    await this.notifyBoth(
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Refund issued',
      `Your payment for ${booking.property.title} has been refunded.`,
    );
    if (landlord) {
      await this.notifyBoth(
        landlord.id,
        landlord.email,
        NotificationType.BOOKING_STATUS,
        'Booking refunded',
        `The tenant was refunded for ${booking.property.title} before moving in. The listing remains available.`,
      );
    }

    return updatedBooking;
  }

  /// `POST /bookings/:id/reject` — the landlord's own distinct
  /// outright-rejection lever, separate from declining an inspection date
  /// (BookingsService.respondToInspection) — full refund, **no** platform
  /// fee withheld (unlike the tenant-initiated `refundBookingBeforeMoveIn`,
  /// which keeps the 0.2% cut), since this is the landlord's decision, not
  /// the tenant's.
  async rejectBookingByLandlord(bookingId: string, landlordId: string) {
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      include: { property: true, tenant: true },
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.property.landlordId !== landlordId) {
      throw new ForbiddenException('You do not own the property this booking is for');
    }
    if (booking.property.category === PropertyCategory.SHORTLET) {
      throw new BadRequestException('Shortlet bookings are handled through accept/decline, not this action');
    }
    if (!PRE_MOVE_IN_STATUSES.includes(booking.status)) {
      throw new BadRequestException('This booking can no longer be rejected');
    }

    const payment = await this.prisma.payment.findFirst({
      where: { bookingId, status: PaymentStatus.PAID_HELD },
      orderBy: { createdAt: 'desc' },
    });
    if (!payment) throw new BadRequestException('No held payment found for this booking');

    await this.paystack.refundTransaction(payment.paystackReference);

    const [updatedBooking] = await this.prisma.$transaction([
      this.prisma.booking.update({ where: { id: bookingId }, data: { status: BookingStatus.DECLINED } }),
      this.prisma.payment.update({
        where: { id: payment.id },
        data: { status: PaymentStatus.REFUNDED, refundedAt: new Date(), platformFeeAmount: 0 },
      }),
    ]);

    await this.notifyBoth(
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Booking rejected',
      `The landlord was unable to proceed with your booking for ${booking.property.title}. You've been fully refunded.`,
    );

    return updatedBooking;
  }

  // ---------------------------------------------------------------------
  // Webhook entry point
  // ---------------------------------------------------------------------

  /// Called by PaystackController on a verified `charge.success` event.
  /// Idempotency: Paystack retries webhook delivery, so this only acts the
  /// first time it sees a given reference still INITIATED — every later
  /// delivery (or a reference belonging to a Payment we already marked
  /// FAILED as "superseded" by a later attempt, see chargeBooking) is a
  /// silent no-op.
  async handleChargeSuccess(reference: string): Promise<void> {
    // A conditional updateMany (not findUnique-then-update) so the
    // INITIATED -> PAID_HELD transition is atomic at the database level —
    // two concurrent webhook deliveries for the same reference can only
    // ever have one of them see count === 1 and proceed past this point.
    const { count } = await this.prisma.payment.updateMany({
      where: { paystackReference: reference, status: PaymentStatus.INITIATED },
      data: { status: PaymentStatus.PAID_HELD, paidAt: new Date() },
    });
    if (count === 0) {
      this.logger.log(`Webhook charge.success for ${reference} ignored — unknown reference or already processed`);
      return;
    }

    const payment = await this.prisma.payment.findUniqueOrThrow({ where: { paystackReference: reference } });

    if (payment.purpose === PaymentPurpose.MARKETPLACE_ORDER_ITEM) {
      await this.onOrderItemPaid(payment);
    } else {
      await this.onBookingPaid(payment);
    }
  }

  private async onOrderItemPaid(payment: Payment): Promise<void> {
    const item = await this.prisma.marketplaceOrderItem.findUnique({
      where: { id: payment.orderItemId! },
      include: { order: { select: { buyerId: true } }, vendor: { select: { userId: true, businessName: true } } },
    });
    if (!item) {
      this.logger.error(`Payment ${payment.id} paid but its order item ${payment.orderItemId} is gone`);
      return;
    }
    await this.notifyBoth(
      item.order.buyerId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Payment held',
      `Your payment for ${item.productName} is confirmed and held until you confirm delivery.`,
    );
    await this.notifyBoth(
      item.vendor.userId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Order paid',
      `Payment for ${item.productName} is confirmed and held until the buyer confirms receipt.`,
    );
  }

  private async onBookingPaid(payment: Payment): Promise<void> {
    const booking = await this.prisma.booking.findUnique({
      where: { id: payment.bookingId! },
      include: { property: true, tenant: true },
    });
    if (!booking) {
      this.logger.error(`Payment ${payment.id} paid but its booking ${payment.bookingId} is gone`);
      return;
    }

    if (booking.status === BookingStatus.MOVED_IN) {
      await this.releaseRenewal(payment, booking);
      return;
    }

    if (booking.property.category === PropertyCategory.SHORTLET) {
      await this.releaseShortletInstant(payment, booking);
      return;
    }

    await this.prisma.booking.update({ where: { id: booking.id }, data: { status: BookingStatus.PAID_AWAITING_INSPECTION } });
    await this.notifyBoth(
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Payment confirmed',
      `Your payment for ${booking.property.title} is confirmed and held. Book an inspection whenever you're ready, or request a refund, from your bookings.`,
    );
    await this.notifyBoth(
      booking.property.landlordId,
      undefined,
      NotificationType.BOOKING_STATUS,
      'Tenant paid',
      `A tenant paid for ${booking.property.title}. Funds are held until an inspection is done and they confirm move-in.`,
    );
  }

  /// Shortlet: no hold, no separate click — release happens the instant
  /// the charge clears. If the release itself fails (e.g. a transient
  /// Paystack outage), the Payment is deliberately left at PAID_HELD and
  /// the booking is *not* advanced — see the class-level note in the
  /// report on why this fails safe instead of confirming a stay HomeServant
  /// hasn't actually been able to pay out for yet.
  private async releaseShortletInstant(payment: Payment, booking: { id: string; propertyId: string; requestedDate: Date | null; nights: number | null; property: { landlordId: string; title: string }; tenantId: string; tenant: { email: string } }): Promise<void> {
    if (!booking.requestedDate || !booking.nights) {
      this.logger.error(`Shortlet booking ${booking.id} paid but is missing requestedDate/nights`);
      return;
    }
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: booking.property.landlordId } });

    try {
      await this.releasePaymentToRecipient(payment, {
        bankCode: landlord.bankCode,
        accountNumber: landlord.accountNumber,
        accountName: landlord.accountName,
        reason: `HomeServant shortlet release — ${booking.property.title}`,
      });
    } catch (err) {
      this.logger.error(`Shortlet release failed for booking ${booking.id}, payment ${payment.id}: ${(err as Error).message}. Payment left PAID_HELD for manual follow-up.`);
      return;
    }

    const leaseStart = booking.requestedDate;
    const leaseEnd = addDays(leaseStart, booking.nights);
    await this.prisma.booking.update({
      where: { id: booking.id },
      data: { status: BookingStatus.PAID, leaseStartDate: leaseStart, leaseEndDate: leaseEnd },
    });

    await this.notifyBoth(
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Booking confirmed',
      `Your shortlet stay at ${booking.property.title} is confirmed and paid.`,
    );
    await this.notifyBoth(
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Shortlet booked and paid',
      `${booking.property.title} was booked and your payout has been released.`,
    );
  }

  /// Renewal: like move-in, no hold — release happens immediately since
  /// the tenant is already living there. Extends leaseEndDate from its
  /// *current* value (not from "now"), and resets the reminder de-dupe
  /// field so the next cycle's 30/15/0-day reminders can fire again.
  private async releaseRenewal(payment: Payment, booking: { id: string; leaseEndDate: Date | null; property: { landlordId: string; title: string; rentDurationMonths: number | null }; tenantId: string; tenant: { email: string } }): Promise<void> {
    if (!booking.leaseEndDate || !booking.property.rentDurationMonths) {
      this.logger.error(`Renewal payment ${payment.id} succeeded but booking ${booking.id} is missing leaseEndDate/rentDurationMonths`);
      return;
    }
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: booking.property.landlordId } });

    try {
      await this.releasePaymentToRecipient(payment, {
        bankCode: landlord.bankCode,
        accountNumber: landlord.accountNumber,
        accountName: landlord.accountName,
        reason: `HomeServant rent renewal release — ${booking.property.title}`,
      });
    } catch (err) {
      this.logger.error(`Renewal release failed for booking ${booking.id}, payment ${payment.id}: ${(err as Error).message}. Payment left PAID_HELD for manual follow-up; lease NOT extended.`);
      return;
    }

    const newLeaseEnd = addMonths(booking.leaseEndDate, booking.property.rentDurationMonths);
    await this.prisma.booking.update({
      where: { id: booking.id },
      data: { leaseEndDate: newLeaseEnd, lastRentReminderDaysOut: null },
    });

    await this.notifyBoth(
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Lease renewed',
      `Your lease for ${booking.property.title} has been renewed.`,
    );
    await this.notifyBoth(
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Renewal paid',
      `Your tenant renewed their lease for ${booking.property.title} and your payout has been released.`,
    );
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  /// Creates (or reuses, if already done for this Payment) a Paystack
  /// transfer recipient, then sends the recipient's share
  /// (amount - platformFeeAmount) and marks the Payment RELEASED. Throws
  /// if payout details are missing or if Paystack itself rejects the
  /// transfer — callers decide how to handle that (webhook paths log and
  /// leave the Payment PAID_HELD; the explicit moved-in/confirm-received
  /// endpoints let the exception surface as a 500 so the user sees the
  /// failure and can retry the click).
  private async releasePaymentToRecipient(
    payment: Payment,
    opts: { bankCode: string | null; accountNumber: string | null; accountName: string | null; reason: string },
  ): Promise<void> {
    if (!opts.bankCode || !opts.accountNumber || !opts.accountName) {
      throw new InternalServerErrorException('The recipient has no payout account on file — release could not be completed');
    }

    let recipientCode = payment.transferRecipientCode;
    if (!recipientCode) {
      recipientCode = await this.paystack.createTransferRecipient(opts.bankCode, opts.accountNumber, opts.accountName);
      await this.prisma.payment.update({ where: { id: payment.id }, data: { transferRecipientCode: recipientCode } });
    }

    const recipientAmountKobo = payment.amount - payment.platformFeeAmount;
    // `payment.id` as the transfer reference means a retry after our own
    // RELEASED-marking write fails below can't cause a second real payout
    // for the same Payment — see initiateTransfer's doc comment.
    await this.paystack.initiateTransfer(recipientAmountKobo, recipientCode, opts.reason, payment.id);
    await this.prisma.payment.update({ where: { id: payment.id }, data: { status: PaymentStatus.RELEASED, releasedAt: new Date() } });
  }

  private fee(amountKobo: number, bps: number): number {
    return Math.round((amountKobo * bps) / BPS_DENOMINATOR);
  }

  private generateReference(prefix: string): string {
    return `${prefix}_${Date.now()}_${randomBytes(6).toString('hex')}`;
  }

  /// In-app notification + best-effort email, mirroring the pattern
  /// already used across ChatService/AdminService/ReportsService. `email`
  /// is optional purely so call sites that only have a userId handy (the
  /// landlord/vendor id, not yet the fetched User row) don't need an extra
  /// query just to skip the email half — MailService itself is already
  /// best-effort and never throws.
  private async notifyBoth(userId: string, email: string | undefined, type: NotificationType, title: string, body: string): Promise<void> {
    await this.notifications.create(userId, type, title, body);
    if (email) {
      await this.mail.send(email, title, `<p>${body}</p>`, body);
    }
  }
}
