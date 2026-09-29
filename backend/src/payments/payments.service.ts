import { PlatformSettingsService } from '../platform-settings/platform-settings.service';
import { Cron, CronExpression } from '@nestjs/schedule';
import { BadRequestException, ConflictException, ForbiddenException, Injectable, InternalServerErrorException, Logger, NotFoundException } from '@nestjs/common';
import { randomBytes } from 'crypto';
import { BookingStatus, NotificationType, OrderItemStatus, Payment, PaymentPlan, PaymentPurpose, PaymentStatus, PriceUnit, PropertyCategory, VerificationStatus } from '@prisma/client';
import { ChatService } from '../chat/chat.service';
import { formatRent } from '../common/format-rent';
import { assertRentalAvailable } from '../common/rental-availability';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { escapeHtml } from '../common/escape-html';
import { EmailProperty, propertyEmailDetails } from '../common/property-email';

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

/// A monthly tenant can pay the next month from this many days before
/// it's due.
const MONTHLY_PAY_WINDOW_DAYS = 7;

function minDate(a: Date, b: Date): Date {
  return a.getTime() <= b.getTime() ? a : b;
}

/// The single home for HomeServant's escrow logic: charge in full, hold
/// in HomeServant's own Paystack balance, and later Transfer the
/// recipient's 95% share (HomeServant keeps 5%) — never Paystack Split
/// Payments. Used by both BookingsService (rentals/shortlets) and
/// MarketplaceOrdersService (order items), so every money-movement rule
/// lives in one place instead of being re-derived per feature.
/// How long a payout lock may be held before it's treated as abandoned.
const PAYOUT_LOCK_MS = 10 * 60 * 1000;

/// Paystack transfer states that mean the money did NOT go out, so a new
/// attempt (with a fresh reference) is safe. Anything else — success,
/// pending, processing, otp, queued, received — counts as sent.
const RETRYABLE_TRANSFER_STATUSES = new Set(['failed', 'reversed', 'abandoned', 'rejected']);

/// Start of the error recorded when a payout can't be sent because
/// HomeServant's Paystack balance is lower than it. Such payouts are
/// retried automatically (see retryLowBalancePayouts) once money arrives.
export const LOW_BALANCE_ERROR = "HomeServant's Paystack balance is too low";

/// Paystack's own wording for a transfer bigger than the balance
/// ("Your balance is not enough to fulfil this request", "Insufficient
/// balance"), or ours from the balance check below.
export function isLowBalanceError(message: string | null | undefined): boolean {
  return !!message && (message.startsWith(LOW_BALANCE_ERROR) || /balance.*(not enough|insufficient)|insufficient.*balance/i.test(message));
}

function lowBalanceMessage(availableKobo: number | null, neededKobo: number): string {
  const naira = (kobo: number) => `NGN ${(kobo / 100).toLocaleString('en-NG', { maximumFractionDigits: 2 })}`;
  return (
    `${LOW_BALANCE_ERROR} to send this payout (${availableKobo === null ? 'balance unknown' : `${naira(availableKobo)} available`}, ` +
    `${naira(neededKobo)} needed). Payouts are sent from the Paystack balance: fund it, or have Paystack keep collected ` +
    `payments there instead of settling them to the bank. It's retried automatically every 30 minutes.`
  );
}

/// What a landlord is told when a transfer didn't go through first time.
const DELAYED_PAYOUT_LINE =
  "Your payout is delayed by a problem sending it to your bank. HomeServant has been alerted and will send it shortly; check your bank details in the app.";

/// What a landlord is told when their payout is held for verification.
const HELD_PAYOUT_LINE =
  "HomeServant is holding your payout until your identity is verified. Open your Profile and tap \"Get verified\"; it's released automatically once you are.";

@Injectable()
export class PaymentsService {
  private readonly logger = new Logger('Payments');

  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
    private readonly chat: ChatService,
    private readonly platform: PlatformSettingsService,
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
    // Same guarantees as rent refunds: one money action at a time, and
    // Paystack is asked first whether it was already refunded.
    await this.withMoneyLock(payment.id, async () => {
      await this.refundHeldPayment(payment, payment.amount, 'MARKETPLACE');
      await this.prisma.payment.update({
        where: { id: payment.id },
        data: { status: PaymentStatus.REFUNDED, refundedAt: new Date(), platformFeeAmount: 0, refundLastError: null },
      });
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
    if (!isShortlet) await assertRentalAvailable(this.prisma, booking.propertyId, tenantId);
    if (booking.property.category !== PropertyCategory.SHORTLET && !booking.property.rentDurationMonths) {
      throw new BadRequestException('This property has no rent duration configured — contact the landlord');
    }
    if (booking.property.category === PropertyCategory.SHORTLET && !booking.nights) {
      throw new BadRequestException('This booking is missing its number of nights');
    }

    return this.chargeBooking(booking, booking.tenant.email);
  }

  /// Asks Paystack about every still-open (INITIATED) charge on this
  /// booking and processes any that actually succeeded, exactly as the
  /// webhook would (it's idempotent, so a webhook arriving later is a
  /// no-op). True if one had been paid.
  private async settleOpenBookingCharges(bookingId: string): Promise<boolean> {
    const open = await this.prisma.payment.findMany({
      where: { bookingId, status: PaymentStatus.INITIATED },
      select: { paystackReference: true },
    });
    let paid = false;
    for (const { paystackReference } of open) {
      if ((await this.paystack.verifyCharge(paystackReference)) === 'success') {
        await this.handleChargeSuccess(paystackReference);
        paid = true;
      }
    }
    return paid;
  }

  /// `POST /bookings/confirm-payment` — called by the app when Paystack
  /// sends the payer back (with `?reference=` on the URL), so the booking
  /// shows as paid straight away instead of whenever the webhook arrives.
  /// Only the payer can confirm their own charge; anything not yet
  /// successful at Paystack is left alone.
  async confirmBookingCharge(reference: string, payerId: string): Promise<{ paid: boolean }> {
    const payment = await this.prisma.payment.findUnique({
      where: { paystackReference: reference },
      select: { payerId: true, status: true, purpose: true },
    });
    if (!payment || payment.payerId !== payerId || payment.purpose !== PaymentPurpose.RENTAL_BOOKING) {
      throw new NotFoundException('Payment not found');
    }
    if (payment.status !== PaymentStatus.INITIATED) {
      return { paid: payment.status !== PaymentStatus.FAILED };
    }
    if ((await this.paystack.verifyCharge(reference)) !== 'success') return { paid: false };
    await this.handleChargeSuccess(reference);
    return { paid: true };
  }

  /// `POST /bookings/:id/renew` — tenant-only, only for an active
  /// (MOVED_IN) non-Shortlet lease, within RENEWAL_WINDOW_DAYS of its
  /// current leaseEndDate. Charges again exactly like the first payment;
  /// what makes this a *renewal* rather than a fresh payment is purely
  /// that the booking is already MOVED_IN when the webhook later sees the
  /// charge succeed (see handleChargeSuccess) — no separate flag needed.
  ///
  /// [expected] is what the tenant was shown by [renewalQuote] and agreed
  /// to pay. If the landlord changed the rent or lease length since, the
  /// charge is refused (409) so the tenant is never charged an amount they
  /// didn't see. Older clients that send nothing are charged as before.
  async renewBooking(bookingId: string, tenantId: string, expected?: { amount?: number; leaseMonths?: number }) {
    const booking = await this.loadRenewableBooking(bookingId, tenantId);
    const property = booking.property;
    if (
      (expected?.amount !== undefined && expected.amount !== property.price) ||
      (expected?.leaseMonths !== undefined && expected.leaseMonths !== property.rentDurationMonths)
    ) {
      throw new ConflictException(
        `The landlord changed the terms: renewing is now ${formatRent(property.price, property.priceUnit)} for ` +
          `${property.rentDurationMonths} months. Please review the new amount before renewing.`,
      );
    }
    return this.chargeBooking(booking, booking.tenant.email, { renewal: true });
  }

  /// `GET /bookings/:id/renewal-quote` — exactly what [renewBooking] would
  /// charge right now, and what the tenant paid last time, so the app can
  /// show (and flag) the amount before the tenant confirms.
  async renewalQuote(bookingId: string, tenantId: string) {
    const booking = await this.loadRenewableBooking(bookingId, tenantId);
    const { property } = booking;
    const leaseMonths = property.rentDurationMonths!;
    return {
      amount: property.price,
      // Monthly: what's charged now is the first month of the new term.
      paymentPlan: booking.paymentPlan,
      monthlyAmount: booking.paymentPlan === PaymentPlan.MONTHLY ? Math.ceil(property.price / 12) : null,
      priceUnit: property.priceUnit,
      leaseMonths,
      previousAmount: booking.priceSnapshot,
      previousPriceUnit: booking.priceUnitSnapshot,
      currentLeaseEnd: booking.leaseEndDate,
      newLeaseEnd: addMonths(booking.leaseEndDate!, leaseMonths),
    };
  }

  /// Every rule for renewing, shared by the quote and the charge.
  private async loadRenewableBooking(bookingId: string, tenantId: string) {
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
    const evicted = await this.prisma.evictionRequest.count({ where: { bookingId, status: 'APPROVED' } });
    if (evicted > 0) {
      throw new BadRequestException('This tenancy was ended by an approved eviction and cannot be renewed');
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
    if (
      booking.paymentPlan === PaymentPlan.MONTHLY &&
      booking.rentPaidThrough &&
      booking.rentPaidThrough.getTime() < booking.leaseEndDate.getTime()
    ) {
      throw new BadRequestException("Pay the remaining months of this lease before renewing — see \"Pay next month's rent\"");
    }
    const daysUntilEnd = (booking.leaseEndDate.getTime() - Date.now()) / MS_PER_DAY;
    if (daysUntilEnd > RENEWAL_WINDOW_DAYS) {
      throw new BadRequestException(`Too early to renew — you can renew starting ${RENEWAL_WINDOW_DAYS} days before your lease ends`);
    }
    return booking;
  }

  private async chargeBooking(
    booking: {
      id: string;
      propertyId: string;
      tenantId: string;
      nights: number | null;
      paymentPlan?: PaymentPlan;
      monthlyRent?: number | null;
      property: { price: number; priceUnit: PriceUnit; landlordId: string; category: PropertyCategory };
    },
    tenantEmail: string,
    { renewal = false, installment = false }: { renewal?: boolean; installment?: boolean } = {},
  ) {
    // The tenant may already have paid an earlier checkout whose webhook
    // hasn't landed yet. Starting a new charge marks that one FAILED, so its
    // webhook would then be ignored and they'd be asked to pay twice.
    if (await this.settleOpenBookingCharges(booking.id)) {
      throw new BadRequestException("You've already paid for this — see your Booking History.");
    }
    await this.prisma.payment.updateMany({
      where: { bookingId: booking.id, status: PaymentStatus.INITIATED },
      data: { status: PaymentStatus.FAILED },
    });

    const priceNaira = booking.property.price;
    // A monthly plan charges one month at a time: the first month, each
    // later month, and the first month of a renewed term. The agreed amount
    // is kept for the current term; a renewal takes the current price.
    const monthlyNaira =
      booking.paymentPlan === PaymentPlan.MONTHLY
        ? renewal
          ? Math.ceil(priceNaira / 12)
          : (booking.monthlyRent ?? Math.ceil(priceNaira / 12))
        : null;
    const amountNaira =
      monthlyNaira ?? (booking.property.category === PropertyCategory.SHORTLET ? priceNaira * (booking.nights ?? 1) : priceNaira);
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
      // A first payment snapshots the price now (the booking isn't paid
      // yet, so nothing else relies on it). A renewal keeps the price the
      // tenant last paid until this charge actually succeeds; see
      // releaseRenewal.
      ...(renewal || installment
        ? []
        : [
            this.prisma.booking.update({
              where: { id: booking.id },
              data: { priceSnapshot: priceNaira, priceUnitSnapshot: booking.property.priceUnit },
            }),
          ]),
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

  /// `POST /bookings/:id/pay-month` — a tenant on a MONTHLY plan paying the
  /// next month of an active lease. Open from [MONTHLY_PAY_WINDOW_DAYS]
  /// days before it's due, and any time once overdue; once every month of
  /// the term is paid, the next step is renewing. The money goes straight
  /// to the landlord when it clears (see [releaseMonthlyInstallment]).
  async payMonthlyRent(bookingId: string, tenantId: string) {
    const booking = await this.prisma.booking.findUnique({
      where: { id: bookingId },
      include: { property: true, tenant: true },
    });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.tenantId !== tenantId) throw new ForbiddenException('Not your booking');
    if (booking.paymentPlan !== PaymentPlan.MONTHLY) throw new BadRequestException('This booking is paid in full, not monthly');
    if (booking.status !== BookingStatus.MOVED_IN || !booking.leaseEndDate || !booking.rentPaidThrough) {
      throw new BadRequestException('Monthly rent is paid once you have moved in');
    }
    const evicted = await this.prisma.evictionRequest.count({ where: { bookingId, status: 'APPROVED' } });
    if (evicted > 0) throw new BadRequestException('This tenancy was ended by an approved eviction');
    if (booking.rentPaidThrough.getTime() >= booking.leaseEndDate.getTime()) {
      throw new BadRequestException('Every month of this lease is paid. Renew from your booking history to stay on.');
    }
    const daysUntilDue = (booking.rentPaidThrough.getTime() - Date.now()) / MS_PER_DAY;
    if (daysUntilDue > MONTHLY_PAY_WINDOW_DAYS) {
      throw new BadRequestException(
        `Next month's rent can be paid from ${MONTHLY_PAY_WINDOW_DAYS} days before it's due (${booking.rentPaidThrough.toDateString()})`,
      );
    }
    return this.chargeBooking(booking, booking.tenant.email, { installment: true });
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
    const rentDurationMonths = booking.property.rentDurationMonths;

    // Under the money lock, so a refund (tenant, landlord or admin) can't
    // happen at the same moment: whichever comes second is refused.
    const { outcome, updatedBooking } = await this.withMoneyLock(payment.id, async () => {
      const now = await this.prisma.booking.findUniqueOrThrow({ where: { id: bookingId } });
      if (now.status !== BookingStatus.INSPECTION_CONFIRMED) throw new BadRequestException('This booking is not awaiting move-in');
      const held = await this.prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
      const outcome = await this.releaseOrHoldForLandlord(held, landlord, `HomeServant rent release — ${booking.property.title}`, true);

      const leaseStart = new Date();
      const leaseEnd = addMonths(leaseStart, rentDurationMonths);

      const [updatedBooking] = await this.prisma.$transaction([
      this.prisma.booking.update({
        where: { id: bookingId },
        data: {
          status: BookingStatus.MOVED_IN,
          leaseStartDate: leaseStart,
          leaseEndDate: leaseEnd,
          // Monthly: the first month (the payment just released) is covered.
          ...(booking.paymentPlan === PaymentPlan.MONTHLY
            ? { rentPaidThrough: minDate(addMonths(leaseStart, 1), leaseEnd) }
            : {}),
        },
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
      return { outcome, updatedBooking };
    });

    await this.notifyAboutBooking(booking, 
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Welcome home!',
      `You've moved into ${booking.property.title}. Your tenancy agreement is ready in your booking history.`,
    );
    await this.notifyAboutBooking(booking, 
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Tenant moved in',
      outcome === 'held'
        ? `Your tenant has moved into ${booking.property.title}. ${HELD_PAYOUT_LINE}`
        : outcome === 'failed'
        ? `Your tenant has moved into ${booking.property.title}. ${DELAYED_PAYOUT_LINE}`
        : `Your tenant has moved into ${booking.property.title} and your payout has been released.`,
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
    return this.refundBooking(bookingId, 'TENANT', { actorId: tenantId });
  }

  /// `POST /bookings/:id/reject` — the landlord's own distinct
  /// outright-rejection lever, separate from declining an inspection date
  /// (BookingsService.respondToInspection) — full refund, **no** platform
  /// fee withheld (unlike the tenant-initiated `refundBookingBeforeMoveIn`,
  /// which keeps the 0.2% cut), since this is the landlord's decision, not
  /// the tenant's.
  async rejectBookingByLandlord(bookingId: string, landlordId: string) {
    return this.refundBooking(bookingId, 'LANDLORD', { actorId: landlordId });
  }

  /// Super admin refund from the Payouts screen: full refund of money
  /// HomeServant still holds, for a tenant who hasn't moved in (or whose
  /// shortlet stay hasn't started). The booking ends as Refunded, so the
  /// tenant's own Refund is no longer offered — and refused if tried.
  async adminRefundBooking(paymentId: string, adminId: string, reason: string) {
    const payment = await this.prisma.payment.findUnique({ where: { id: paymentId }, select: { bookingId: true, purpose: true } });
    if (!payment?.bookingId || payment.purpose !== PaymentPurpose.RENTAL_BOOKING) throw new NotFoundException('Payment not found');
    const trimmed = reason.trim();
    if (trimmed.length < 10) throw new BadRequestException('Give a reason (at least 10 characters); the tenant and landlord see it');
    return this.refundBooking(payment.bookingId, 'ADMIN', { actorId: adminId, reason: trimmed });
  }

  /// One refund flow for everyone, so the same guarantees apply to all:
  ///  - the booking's state and the held payment are re-checked *inside*
  ///    the money lock, so a refund can't overlap a move-in payout, another
  ///    refund, or a retry (whoever is second is told it's in progress or
  ///    already done);
  ///  - Paystack is asked first whether this charge was already refunded
  ///    (see [refundHeldPayment]), so it is never refunded twice;
  ///  - once refunded, the booking is REFUNDED/DECLINED and the payment
  ///    REFUNDED, which every refund path checks first.
  /// TENANT: before move-in, keeps the 0.2% fee. LANDLORD: before move-in,
  /// full refund, booking DECLINED. ADMIN: full refund, before move-in or
  /// before a shortlet stay starts.
  private async refundBooking(
    bookingId: string,
    kind: 'TENANT' | 'LANDLORD' | 'ADMIN',
    opts: { actorId: string; reason?: string },
  ) {
    const booking = await this.prisma.booking.findUnique({ where: { id: bookingId }, include: { property: true, tenant: true } });
    if (!booking) throw new NotFoundException('Booking not found');
    if (kind === 'TENANT' && booking.tenantId !== opts.actorId) throw new ForbiddenException('Not your booking');
    if (kind === 'LANDLORD' && booking.property.landlordId !== opts.actorId) {
      throw new ForbiddenException('You do not own the property this booking is for');
    }
    const isShortlet = booking.property.category === PropertyCategory.SHORTLET;
    if (isShortlet && kind === 'TENANT') throw new BadRequestException('Shortlet payments release instantly and cannot be refunded through this action');
    if (isShortlet && kind === 'LANDLORD') throw new BadRequestException('Shortlet bookings are handled through accept/decline, not this action');

    const payment = await this.prisma.payment.findFirst({ where: { bookingId }, orderBy: { createdAt: 'desc' } });
    if (!payment) throw new BadRequestException('No payment found for this booking');
    if (payment.status === PaymentStatus.REFUNDED) throw new BadRequestException('This payment has already been refunded');
    if (payment.status !== PaymentStatus.PAID_HELD) {
      throw new BadRequestException(
        payment.status === PaymentStatus.RELEASED ? 'This payment has already been paid out to the landlord' : 'No held payment found for this booking',
      );
    }

    const refundAmountKobo = kind === 'TENANT' ? payment.amount - this.fee(payment.amount, REFUND_FEE_BPS) : payment.amount;
    const updated = await this.withMoneyLock(payment.id, async () => {
      // Re-check now that nothing else can move this money.
      const now = await this.prisma.booking.findUniqueOrThrow({ where: { id: bookingId } });
      const stillHeld = await this.prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
      if (stillHeld.status !== PaymentStatus.PAID_HELD) throw new BadRequestException('This payment has already been refunded or paid out');
      const refundable = isShortlet
        ? now.status === BookingStatus.ACCEPTED ||
          (now.status === BookingStatus.PAID && !!now.leaseStartDate && now.leaseStartDate > new Date())
        : PRE_MOVE_IN_STATUSES.includes(now.status);
      if (!refundable) {
        throw new BadRequestException(
          kind === 'LANDLORD'
            ? 'This booking can no longer be rejected'
            : isShortlet
              ? 'This stay has already started, so it can no longer be refunded'
              : 'Only a paid booking that hasn’t been moved into yet can be refunded',
        );
      }

      if (kind === 'ADMIN') {
        // Kept even if the refund fails, so "Retry refund" can reuse it.
        await this.prisma.payment.update({ where: { id: payment.id }, data: { refundReason: opts.reason, refundedById: opts.actorId } });
      }
      await this.refundHeldPayment(stillHeld, refundAmountKobo, kind);
      const [updatedBooking] = await this.prisma.$transaction([
        this.prisma.booking.update({
          where: { id: bookingId },
          data: { status: kind === 'LANDLORD' ? BookingStatus.DECLINED : BookingStatus.REFUNDED },
        }),
        this.prisma.payment.update({
          where: { id: payment.id },
          data: {
            status: PaymentStatus.REFUNDED,
            refundedAt: new Date(),
            platformFeeAmount: payment.amount - refundAmountKobo,
            heldForVerificationAt: null,
            refundLastError: null,
            payoutLastError: null,
            ...(kind === 'ADMIN' ? { refundedById: opts.actorId, refundReason: opts.reason } : {}),
          },
        }),
      ]);
      return updatedBooking;
    });

    const landlord = await this.prisma.user.findUnique({ where: { id: booking.property.landlordId }, select: { id: true, email: true } });
    const title = booking.property.title;
    if (kind === 'TENANT') {
      // Messaging between them closes on a refund (ChatService.landlordTenantBlockReason);
      // say so in their existing chat, if they have one.
      await this.postBookingSystemMessage(
        booking,
        `Refund initiated by the tenant for ${title}. Further messaging is no longer available unless the tenant books and pays again.`,
        false,
      );
      await this.notifyAboutBooking(booking, booking.tenantId, booking.tenant.email, NotificationType.BOOKING_STATUS, 'Refund issued', `Your payment for ${title} has been refunded.`);
      if (landlord) {
        await this.notifyBoth(
          landlord.id,
          landlord.email,
          NotificationType.BOOKING_STATUS,
          'Booking refunded',
          `The tenant was refunded for ${title} before moving in. The listing remains available.`,
        );
      }
    } else if (kind === 'LANDLORD') {
      // The tenant hears about it in Messages too (a thread is started if
      // they never chatted), and the notification opens that chat.
      const threadId = await this.postBookingSystemMessage(
        booking,
        `The landlord rejected this booking for ${title} and the tenant has been fully refunded. Further messaging is no longer available unless the tenant books and pays again.`,
        true,
      );
      await this.notifyAboutBooking(booking, 
        booking.tenantId,
        booking.tenant.email,
        NotificationType.BOOKING_STATUS,
        'Booking rejected',
        `The landlord was unable to proceed with your booking for ${title}. You've been fully refunded.`,
        threadId ?? undefined,

      );
    } else {
      const threadId = await this.postBookingSystemMessage(
        booking,
        `HomeServant refunded the tenant in full for ${title}. Reason: ${opts.reason}. Further messaging is no longer available unless the tenant books and pays again.`,
        true,
      );
      await this.notifyAboutBooking(booking, 
        booking.tenantId,
        booking.tenant.email,
        NotificationType.BOOKING_STATUS,
        'You have been refunded',
        `HomeServant has refunded your payment for ${title} in full. Reason: ${opts.reason}`,
        threadId ?? undefined,

      );
      if (landlord) {
        await this.notifyBoth(
          landlord.id,
          landlord.email,
          NotificationType.BOOKING_STATUS,
          'Booking refunded by HomeServant',
          `HomeServant refunded the tenant for ${title}. Reason: ${opts.reason}`,
        );
      }
    }
    return updated;
  }

  /// Sends a refund for a held payment (the caller holds the money lock and
  /// marks it REFUNDED). Paystack is asked first how much of the charge is
  /// already refunded: if any is, that refund went through earlier (e.g. our
  /// own write failed afterwards), so nothing is sent again. A failure is
  /// kept on the payment (what was asked, by whom, and why it failed) for
  /// the admin Payouts screen.
  private async refundHeldPayment(payment: Payment, amountKobo: number, requestedBy: string): Promise<void> {
    try {
      const already = await this.paystack.refundedSoFar(payment.paystackReference);
      if (already > 0) {
        this.logger.warn(`Refund for payment ${payment.id}: Paystack already has ${already} kobo refunded; not refunding again`);
        return;
      }
      await this.prisma.payment.update({
        where: { id: payment.id },
        data: { refundRequestedBy: requestedBy, refundRequestedAmount: amountKobo, refundLastAttemptAt: new Date() },
      });
      await this.paystack.refundTransaction(payment.paystackReference, amountKobo === payment.amount ? undefined : amountKobo);
    } catch (error) {
      await this.prisma.payment.update({
        where: { id: payment.id },
        data: {
          refundRequestedBy: requestedBy,
          refundRequestedAmount: amountKobo,
          refundLastAttemptAt: new Date(),
          refundLastError: (error as Error).message.slice(0, 500),
        },
      });
      throw error;
    }
  }

  /// Runs [fn] while holding this payment's money lock (payout OR refund —
  /// one at a time). Throws if another money action holds it.
  private async withMoneyLock<T>(paymentId: string, fn: () => Promise<T>): Promise<T> {
    const claimed = await this.prisma.payment.updateMany({
      where: {
        id: paymentId,
        status: PaymentStatus.PAID_HELD,
        OR: [{ moneyLockedAt: null }, { moneyLockedAt: { lt: new Date(Date.now() - PAYOUT_LOCK_MS) } }],
      },
      data: { moneyLockedAt: new Date() },
    });
    if (claimed.count === 0) {
      const current = await this.prisma.payment.findUnique({ where: { id: paymentId }, select: { status: true } });
      if (current?.status === PaymentStatus.REFUNDED) throw new BadRequestException('This payment has already been refunded');
      if (current?.status === PaymentStatus.RELEASED) throw new BadRequestException('This payment has already been paid out');
      throw new ConflictException('Another payment action is in progress for this booking. Try again in a moment.');
    }
    try {
      return await fn();
    } finally {
      await this.prisma.payment.update({ where: { id: paymentId }, data: { moneyLockedAt: null } });
    }
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
      // A monthly tenant paying the next month of the current term, rather
      // than renewing for a new one.
      if (
        booking.paymentPlan === PaymentPlan.MONTHLY &&
        booking.rentPaidThrough &&
        booking.leaseEndDate &&
        booking.rentPaidThrough.getTime() < booking.leaseEndDate.getTime()
      ) {
        await this.releaseMonthlyInstallment(payment, booking);
        return;
      }
      await this.releaseRenewal(payment, booking);
      return;
    }

    if (booking.property.category === PropertyCategory.SHORTLET) {
      await this.releaseShortletInstant(payment, booking);
      return;
    }

    await this.prisma.booking.update({ where: { id: booking.id }, data: { status: BookingStatus.PAID_AWAITING_INSPECTION } });
    // Opens (or reuses) their chat so both notifications can go straight to
    // it: the tenant can message the landlord from the payment notification.
    const threadId = await this.postBookingSystemMessage(
      booking,
      `Payment confirmed for ${booking.property.title}. The money is held by HomeServant until the tenant moves in. You can now message each other to arrange the inspection.`,
      true,
    );
    await this.notifyAboutBooking(booking, 
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Payment confirmed',
      `Your payment for ${booking.property.title} is confirmed and held. Message the landlord, book an inspection whenever you're ready, or request a refund, from your booking history.`,
      threadId ?? undefined,

    );
    await this.notifyAboutBooking(booking, 
      booking.property.landlordId,
      undefined,
      NotificationType.BOOKING_STATUS,
      'Tenant paid',
      `A tenant paid for ${booking.property.title}. Funds are held until an inspection is done and they confirm move-in.`,
      threadId ?? undefined,

    );
  }

  /// Shortlet: no hold, no separate click — release happens the instant
  /// the charge clears. The stay is confirmed either way: if the payout is
  /// held for verification or the transfer fails (e.g. a Paystack outage),
  /// the Payment stays PAID_HELD and shows on the admin Payouts screen for
  /// a safe retry, rather than leaving a paying guest unconfirmed.
  private async releaseShortletInstant(payment: Payment, booking: { id: string; propertyId: string; requestedDate: Date | null; nights: number | null; property: EmailProperty & { landlordId: string; title: string }; tenantId: string; tenant: { email: string } }): Promise<void> {
    if (!booking.requestedDate || !booking.nights) {
      this.logger.error(`Shortlet booking ${booking.id} paid but is missing requestedDate/nights`);
      return;
    }
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: booking.property.landlordId } });

    const outcome = await this.releaseOrHoldForLandlord(payment, landlord, `HomeServant shortlet release — ${booking.property.title}`);

    const leaseStart = booking.requestedDate;
    const leaseEnd = addDays(leaseStart, booking.nights);
    await this.prisma.booking.update({
      where: { id: booking.id },
      data: { status: BookingStatus.PAID, leaseStartDate: leaseStart, leaseEndDate: leaseEnd },
    });

    const threadId = await this.postBookingSystemMessage(
      booking,
      `Payment confirmed for the stay at ${booking.property.title}. You can now message each other about check-in.`,
      true,
    );
    await this.notifyAboutBooking(booking, 
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Booking confirmed',
      `Your shortlet stay at ${booking.property.title} is confirmed and paid. Message the landlord about check-in from here.`,
      threadId ?? undefined,

    );
    await this.notifyAboutBooking(booking, 
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Shortlet booked and paid',
      outcome === 'held'
        ? `${booking.property.title} was booked and paid. ${HELD_PAYOUT_LINE}`
        : outcome === 'failed'
        ? `${booking.property.title} was booked and paid. ${DELAYED_PAYOUT_LINE}`
        : `${booking.property.title} was booked and your payout has been released.`,
      threadId ?? undefined,

    );
  }

  /// Renewal: like move-in, no hold — release happens immediately since
  /// the tenant is already living there. Extends leaseEndDate from its
  /// *current* value (not from "now"), and resets the reminder de-dupe
  /// field so the next cycle's 30/15/0-day reminders can fire again.
  /// A monthly tenant's payment for the next month cleared: it goes
  /// straight to the landlord (the tenant already lives there, like a
  /// renewal), and the rent is paid a month further.
  private async releaseMonthlyInstallment(
    payment: Payment,
    booking: { id: string; rentPaidThrough: Date | null; leaseEndDate: Date | null; property: EmailProperty & { landlordId: string; title: string }; tenantId: string; tenant: { email: string } },
  ): Promise<void> {
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: booking.property.landlordId } });
    const outcome = await this.releaseOrHoldForLandlord(payment, landlord, `HomeServant monthly rent — ${booking.property.title}`);
    const paidThrough = minDate(addMonths(booking.rentPaidThrough!, 1), booking.leaseEndDate!);
    await this.prisma.booking.update({
      where: { id: booking.id },
      data: { rentPaidThrough: paidThrough, monthlyReminderSentFor: null, monthlyOverdueNotifiedFor: null },
    });
    const until = paidThrough.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
    const naira = `₦${Math.round(payment.amount / KOBO_PER_NAIRA).toLocaleString('en-US')}`;
    await this.notifyAboutBooking(booking, 
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Monthly rent paid',
      `Thanks — your rent for ${booking.property.title} is paid until ${until}.`,
    );
    await this.notifyAboutBooking(booking, 
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Monthly rent received',
      outcome === 'held'
        ? `Your tenant paid ${naira} rent for ${booking.property.title} (paid until ${until}). ${HELD_PAYOUT_LINE}`
        : outcome === 'failed'
          ? `Your tenant paid ${naira} rent for ${booking.property.title} (paid until ${until}). ${DELAYED_PAYOUT_LINE}`
          : `Your tenant paid ${naira} rent for ${booking.property.title} (paid until ${until}) and your payout has been released.`,
    );
  }

  private async releaseRenewal(payment: Payment, booking: { id: string; propertyId: string; leaseEndDate: Date | null; paymentPlan?: PaymentPlan; property: EmailProperty & { landlordId: string; title: string; rentDurationMonths: number | null }; tenantId: string; tenant: { email: string } }): Promise<void> {
    if (!booking.leaseEndDate || !booking.property.rentDurationMonths) {
      this.logger.error(`Renewal payment ${payment.id} succeeded but booking ${booking.id} is missing leaseEndDate/rentDurationMonths`);
      return;
    }
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: booking.property.landlordId } });

    const outcome = await this.releaseOrHoldForLandlord(payment, landlord, `HomeServant rent renewal release — ${booking.property.title}`);

    const newLeaseEnd = addMonths(booking.leaseEndDate, booking.property.rentDurationMonths);
    // The rent actually paid for the new term (a renewal is never a
    // Shortlet, so the whole amount is one period's rent). It becomes the
    // booking's price and the tenancy agreement's rent and end date, so the
    // agreement always matches the current term.
    const paidNaira = Math.round(payment.amount / KOBO_PER_NAIRA);
    const { priceUnit, price } = await this.prisma.property.findUniqueOrThrow({
      where: { id: booking.propertyId },
      select: { priceUnit: true, price: true },
    });
    // Monthly: this charge was the new term's first month; the term's rent
    // is still the yearly price, and the agreed month is what was paid.
    const monthly = booking.paymentPlan === PaymentPlan.MONTHLY;
    const rentPaid = monthly ? price : paidNaira;
    await this.prisma.$transaction([
      this.prisma.booking.update({
        where: { id: booking.id },
        data: {
          leaseEndDate: newLeaseEnd,
          lastRentReminderDaysOut: null,
          priceSnapshot: rentPaid,
          priceUnitSnapshot: priceUnit,
          ...(monthly
            ? {
                monthlyRent: paidNaira,
                rentPaidThrough: minDate(addMonths(booking.leaseEndDate, 1), newLeaseEnd),
                monthlyReminderSentFor: null,
                monthlyOverdueNotifiedFor: null,
              }
            : {}),
        },
      }),
      this.prisma.tenancyAgreement.updateMany({
        where: { bookingId: booking.id },
        data: { rentAmount: rentPaid, priceUnit, leaseEndDate: newLeaseEnd },
      }),
    ]);

    await this.notifyAboutBooking(booking, 
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Lease renewed',
      `Your lease for ${booking.property.title} has been renewed until ${newLeaseEnd.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })} at ${formatRent(rentPaid, priceUnit)}. Your tenancy agreement has been updated.`,
    );
    await this.notifyAboutBooking(booking, 
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Renewal paid',
      outcome === 'held'
        ? `Your tenant renewed their lease for ${booking.property.title}. ${HELD_PAYOUT_LINE}`
        : outcome === 'failed'
        ? `Your tenant renewed their lease for ${booking.property.title}. ${DELAYED_PAYOUT_LINE}`
        : `Your tenant renewed their lease for ${booking.property.title} and your payout has been released.`,
    );
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  /// Sends the recipient's share (amount - platformFeeAmount) and marks the
  /// Payment RELEASED — built so a payment can never be paid out twice:
  ///   1. a database lock lets only one release run per payment;
  ///   2. Paystack is asked first whether the last transfer for this payment
  ///      already exists — if it was sent (or is on its way) it's recorded
  ///      as paid and nothing is sent; a new reference is only used when
  ///      Paystack confirms the previous one failed or was reversed;
  ///   3. the reference is saved before sending, so a crash after Paystack
  ///      accepts it is caught by step 2 next time.
  /// Throws on failure (the error is kept on the Payment for the admin
  /// Payouts screen). Rent payouts go through releaseOrHoldForLandlord,
  /// which turns a failure into 'failed' so the tenant's side still goes
  /// ahead; marketplace confirm-received still surfaces the error.
  private async releasePaymentToRecipient(
    payment: Payment,
    opts: { bankCode: string | null; accountNumber: string | null; accountName: string | null; reason: string },
    lockHeld = false,
  ): Promise<void> {
    if (!lockHeld) {
      const now = await this.prisma.payment.findUnique({ where: { id: payment.id }, select: { status: true } });
      if (now?.status === PaymentStatus.RELEASED) return; // already paid — nothing to do
      return this.withMoneyLock(payment.id, () => this.releasePaymentToRecipient(payment, opts, true));
    }
    try {
      if (!opts.bankCode || !opts.accountNumber || !opts.accountName) {
        throw new InternalServerErrorException('No payout bank account on file for the recipient');
      }
      const current = await this.prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
      if (current.status !== PaymentStatus.PAID_HELD) throw new BadRequestException('This payment is no longer held');

      // Never pay twice: ask Paystack whether the last transfer for this
      // payment already exists before sending anything. (Payments released
      // before this tracking existed used their own id.)
      const lastReference = current.payoutReference ?? payment.id;
      const existing = await this.paystack.verifyTransfer(lastReference);
      if (existing !== 'not_found' && !RETRYABLE_TRANSFER_STATUSES.has(existing)) {
        // Sent, or on its way (pending/processing/otp...): record it, don't resend.
        this.logger.warn(`Payout ${payment.id}: transfer ${lastReference} already exists at Paystack (${existing}); not sending again`);
        await this.markReleased(payment.id, lastReference);
        return;
      }
      // A reference Paystack has never seen can be reused; a failed or
      // reversed one can't, so the next attempt gets a fresh one.
      const reference = existing === 'not_found' ? lastReference : `${payment.id}-r${current.payoutAttempts + 1}`;

      let recipientCode = current.transferRecipientCode;
      if (!recipientCode) {
        recipientCode = await this.paystack.createTransferRecipient(opts.bankCode, opts.accountNumber, opts.accountName);
        await this.prisma.payment.update({ where: { id: payment.id }, data: { transferRecipientCode: recipientCode } });
      }

      // Payouts come out of HomeServant's Paystack balance. Check it first,
      // so a payout it can't cover isn't sent (and counted as an attempt)
      // only to be refused. If the balance can't be read, send anyway —
      // Paystack still refuses what it can't cover.
      const amountKobo = payment.amount - payment.platformFeeAmount;
      const available = await this.paystackBalanceKobo();
      if (available !== null && available < amountKobo) {
        throw new BadRequestException(lowBalanceMessage(available, amountKobo));
      }

      // Record the reference BEFORE sending, so if anything goes wrong after
      // Paystack accepts it, the next attempt finds it above.
      await this.prisma.payment.update({
        where: { id: payment.id },
        data: { payoutReference: reference, payoutAttempts: { increment: 1 }, payoutLastAttemptAt: new Date() },
      });
      try {
        await this.paystack.initiateTransfer(amountKobo, recipientCode, opts.reason, reference);
      } catch (error) {
        if (isLowBalanceError((error as Error).message)) throw new BadRequestException(lowBalanceMessage(available, amountKobo));
        throw error;
      }
      await this.markReleased(payment.id, reference);
    } catch (error) {
      await this.prisma.payment.updateMany({
        where: { id: payment.id, status: PaymentStatus.PAID_HELD },
        data: { payoutLastError: (error as Error).message.slice(0, 500) },
      });
      throw error;
    }
  }

  private async markReleased(paymentId: string, reference: string): Promise<void> {
    await this.prisma.payment.update({
      where: { id: paymentId },
      data: {
        status: PaymentStatus.RELEASED,
        releasedAt: new Date(),
        payoutReference: reference,
        heldForVerificationAt: null,
        payoutLastError: null,
      },
    });
  }

  /// Paystack's `transfer.failed` / `transfer.reversed` webhook: the money
  /// never reached (or came back from) the landlord, so the payment is
  /// owed again and shows on the admin Payouts screen. A retry is safe:
  /// Paystack confirms that reference failed, so a fresh one is used.
  async handleTransferFailed(reference: string, outcome: 'failed' | 'reversed', reason?: string): Promise<void> {
    const payment = await this.prisma.payment.findUnique({ where: { payoutReference: reference } });
    if (!payment || payment.status !== PaymentStatus.RELEASED) return;
    await this.prisma.payment.update({
      where: { id: payment.id },
      data: {
        status: PaymentStatus.PAID_HELD,
        releasedAt: null,
        moneyLockedAt: null,
        payoutLastError: `Transfer ${outcome} at the bank${reason ? `: ${reason}` : ''}`.slice(0, 500),
      },
    });
    this.logger.error(`Payout ${payment.id} (${reference}) ${outcome} after release; back to owed`);
  }

  // ---------------------------------------------------------------------
  // Payout hold for unverified landlords (Platform Controls)
  // ---------------------------------------------------------------------

  /// Pays [landlord] now (or reports 'failed' — see below) — or, when Platform Controls has "Pay unverified
  /// landlords" off and they aren't verified, leaves the money held with
  /// HomeServant (marked [heldForVerificationAt]) for release later. The
  /// tenant's side (move-in, stay, renewal) goes ahead either way.
  private async releaseOrHoldForLandlord(
    payment: Payment,
    landlord: { id: string; bankCode: string | null; accountNumber: string | null; accountName: string | null },
    reason: string,
    lockHeld = false,
  ): Promise<'released' | 'held' | 'failed'> {
    if (!(await this.platform.payUnverifiedLandlords())) {
      const verification = await this.prisma.identityVerification.findUnique({ where: { userId: landlord.id }, select: { status: true } });
      if (verification?.status !== VerificationStatus.APPROVED) {
        await this.prisma.payment.update({ where: { id: payment.id }, data: { heldForVerificationAt: new Date() } });
        this.logger.log(`Payout for payment ${payment.id} held until landlord ${landlord.id} is verified`);
        return 'held';
      }
    }
    try {
      await this.releasePaymentToRecipient(payment, { ...landlord, reason }, lockHeld);
      return 'released';
    } catch (err) {
      // The tenant's side still goes ahead; the payout waits on the admin
      // Payouts screen (with this error) for a safe retry.
      this.logger.error(`Payout for payment ${payment.id} failed: ${(err as Error).message}`);
      return 'failed';
    }
  }

  /// Releases every payout held for [landlordId]'s verification — called when
  /// they're verified, or for everyone when the rule is switched off. A
  /// transfer that fails stays held (logged) for the next attempt. Returns
  /// how many were released.
  async releaseHeldPayoutsForLandlord(landlordId: string): Promise<number> {
    const landlord = await this.prisma.user.findUnique({
      where: { id: landlordId },
      select: { id: true, email: true, bankCode: true, accountNumber: true, accountName: true },
    });
    if (!landlord) return 0;
    const held = await this.prisma.payment.findMany({
      where: { status: PaymentStatus.PAID_HELD, heldForVerificationAt: { not: null }, booking: { property: { landlordId } } },
      include: { booking: { select: { property: { select: { title: true } } } } },
    });
    let released = 0;
    let totalKobo = 0;
    for (const payment of held) {
      try {
        await this.releasePaymentToRecipient(payment, {
          ...landlord,
          reason: `HomeServant held payout release — ${payment.booking?.property.title ?? 'rent'}`,
        });
        released++;
        totalKobo += payment.amount - payment.platformFeeAmount;
      } catch (err) {
        this.logger.error(`Could not release held payout ${payment.id} for landlord ${landlordId}: ${(err as Error).message}`);
      }
    }
    if (released > 0) {
      const naira = (totalKobo / 100).toLocaleString('en-NG', { maximumFractionDigits: 2 });
      await this.notifyBoth(
        landlord.id,
        landlord.email,
        NotificationType.BOOKING_STATUS,
        'Your held payouts have been released',
        `${released} payout${released === 1 ? '' : 's'} (NGN ${naira}) held by HomeServant ${released === 1 ? 'has' : 'have'} been sent to your bank account.`,
      );
    }
    return released;
  }

  /// Every landlord with held payouts — used when "Pay unverified
  /// landlords" is switched back on.
  async releaseAllHeldPayouts(): Promise<number> {
    const rows = await this.prisma.payment.findMany({
      where: { status: PaymentStatus.PAID_HELD, heldForVerificationAt: { not: null } },
      select: { booking: { select: { property: { select: { landlordId: true } } } } },
    });
    const landlordIds = [...new Set(rows.map((r) => r.booking?.property.landlordId).filter((id): id is string => !!id))];
    let released = 0;
    for (const id of landlordIds) released += await this.releaseHeldPayoutsForLandlord(id);
    return released;
  }

  // ---------------------------------------------------------------------
  // Admin: Payouts needing attention
  // ---------------------------------------------------------------------

  /// Rent payouts owed to a landlord that haven't gone out: held for
  /// verification, a transfer that failed (or failed/reversed at the bank
  /// later), or — from before failures were recorded — a shortlet whose
  /// instant payout failed and whose stay was left unconfirmed. Escrow that
  /// is simply waiting for a tenant to move in is NOT listed.
  async stuckPayouts() {
    const legacyCutoff = new Date(Date.now() - 30 * 60 * 1000);
    const rows = await this.prisma.payment.findMany({
      where: {
        purpose: PaymentPurpose.RENTAL_BOOKING,
        status: PaymentStatus.PAID_HELD,
        OR: [
          { heldForVerificationAt: { not: null } },
          { payoutLastError: { not: null } },
          { refundLastError: { not: null } },
          {
            paidAt: { lt: legacyCutoff },
            booking: { status: BookingStatus.ACCEPTED, property: { category: PropertyCategory.SHORTLET } },
          },
        ],
      },
      include: {
        booking: {
          select: {
            id: true,
            status: true,
            leaseStartDate: true,
            property: { select: { id: true, title: true, category: true } },
            tenant: { select: { id: true, fullName: true, email: true } },
          },
        },
        recipient: {
          select: { id: true, fullName: true, email: true, bankName: true, accountNumber: true, identityVerification: { select: { status: true } } },
        },
      },
      orderBy: { paidAt: 'asc' },
      take: 300,
    });
    const payUnverified = await this.platform.payUnverifiedLandlords();
    return rows.map((p) => {
      const verified = p.recipient.identityVerification?.status === VerificationStatus.APPROVED;
      const waitingForVerification = !payUnverified && !verified;
      const bookingStatus = p.booking?.status;
      const isShortlet = p.booking?.property.category === PropertyCategory.SHORTLET;
      // Money still held for a tenant who hasn't moved in / whose stay
      // hasn't started: an admin may refund them (see refundBooking).
      const tenantRefundable = isShortlet
        ? bookingStatus === BookingStatus.ACCEPTED ||
          (bookingStatus === BookingStatus.PAID && !!p.booking?.leaseStartDate && p.booking.leaseStartDate > new Date())
        : !!bookingStatus && PRE_MOVE_IN_STATUSES.includes(bookingStatus);
      if (p.refundLastError) {
        return {
          kind: 'REFUND' as const,
          paymentId: p.id,
          amountKobo: p.refundRequestedAmount ?? p.amount,
          paidAt: p.paidAt,
          heldSince: p.refundLastAttemptAt ?? p.paidAt,
          reason: 'REFUND_FAILED',
          lastError: p.refundLastError,
          requestedBy: p.refundRequestedBy,
          attempts: 0,
          lastAttemptAt: p.refundLastAttemptAt,
          inProgress: !!p.moneyLockedAt && p.moneyLockedAt > new Date(Date.now() - PAYOUT_LOCK_MS),
          canRetry: false,
          canRetryRefund: tenantRefundable,
          canRefundTenant: false,
          landlord: {
            id: p.recipient.id,
            name: p.recipient.fullName || p.recipient.email,
            email: p.recipient.email,
            bankName: p.recipient.bankName,
            accountLast4: p.recipient.accountNumber?.slice(-4) ?? null,
            verified,
          },
          property: p.booking?.property ?? null,
          tenant: p.booking?.tenant ?? null,
          bookingId: p.booking?.id ?? null,
        };
      }
      const reason = waitingForVerification
        ? 'AWAITING_VERIFICATION'
        : !p.recipient.accountNumber
          ? 'NO_BANK_ACCOUNT'
          : p.payoutLastError || !p.heldForVerificationAt
            ? 'FAILED'
            : 'READY'; // held for verification, and the rule no longer applies
      return {
        kind: 'PAYOUT' as const,
        paymentId: p.id,
        amountKobo: p.amount - p.platformFeeAmount,
        paidAt: p.paidAt,
        heldSince: p.heldForVerificationAt ?? p.payoutLastAttemptAt ?? p.paidAt,
        reason,
        lastError: p.payoutLastError ?? (p.heldForVerificationAt ? null : "The instant payout failed (details weren't recorded at the time)"),
        attempts: p.payoutAttempts,
        lastAttemptAt: p.payoutLastAttemptAt,
        inProgress: !!p.moneyLockedAt && p.moneyLockedAt > new Date(Date.now() - PAYOUT_LOCK_MS),
        requestedBy: null,
        canRetry: !waitingForVerification && !!p.recipient.accountNumber,
        canRetryRefund: false,
        canRefundTenant: tenantRefundable,
        landlord: {
          id: p.recipient.id,
          name: p.recipient.fullName || p.recipient.email,
          email: p.recipient.email,
          bankName: p.recipient.bankName,
          accountLast4: p.recipient.accountNumber?.slice(-4) ?? null,
          verified,
        },
        property: p.booking?.property ?? null,
        tenant: p.booking?.tenant ?? null,
        bookingId: p.booking?.id ?? null,
      };
    });
  }

  /// HomeServant's current Paystack balance, for the admin Payouts screen
  /// (null if Paystack can't be asked right now).
  async paystackBalanceKobo(): Promise<number | null> {
    try {
      return await this.paystack.balanceKobo();
    } catch {
      return null;
    }
  }

  /// Payouts that failed only because the Paystack balance was too low are
  /// retried every 30 minutes, oldest first, so landlords are paid as soon
  /// as money is available without an admin pressing Retry. Each retry
  /// goes through retryPayout (locked, and Paystack is asked first whether
  /// it already went out), so it can never pay twice. Stops at the first
  /// one the balance still can't cover.
  @Cron(CronExpression.EVERY_30_MINUTES)
  async retryLowBalancePayouts(): Promise<number> {
    const waiting = await this.prisma.payment.findMany({
      where: { purpose: PaymentPurpose.RENTAL_BOOKING, status: PaymentStatus.PAID_HELD, payoutLastError: { not: null } },
      select: { id: true, payoutLastError: true },
      orderBy: { paidAt: 'asc' },
    });
    let paid = 0;
    for (const p of waiting.filter((w) => isLowBalanceError(w.payoutLastError))) {
      try {
        await this.retryPayout(p.id);
        paid++;
      } catch (err) {
        if (isLowBalanceError((err as Error).message)) break;
        this.logger.warn(`Automatic payout retry for ${p.id} failed: ${(err as Error).message}`);
      }
    }
    if (paid > 0) this.logger.log(`Automatic payout retry sent ${paid} payout(s)`);
    return paid;
  }

  async stuckPayoutCount(): Promise<number> {
    return (await this.stuckPayouts()).length;
  }

  /// Super admin "Retry refund": repeats exactly the refund that failed
  /// (same requester, same amount rules), through the same locked,
  /// check-Paystack-first refund flow.
  async retryRefund(paymentId: string, adminId: string) {
    const payment = await this.prisma.payment.findUnique({
      where: { id: paymentId },
      include: { booking: { include: { property: true } } },
    });
    if (!payment?.booking || payment.purpose !== PaymentPurpose.RENTAL_BOOKING) throw new NotFoundException('Payment not found');
    if (payment.status === PaymentStatus.REFUNDED) return { status: 'ALREADY_REFUNDED' as const };
    const kind = payment.refundRequestedBy;
    if (kind === 'TENANT') await this.refundBooking(payment.booking.id, 'TENANT', { actorId: payment.booking.tenantId });
    else if (kind === 'LANDLORD') await this.refundBooking(payment.booking.id, 'LANDLORD', { actorId: payment.booking.property.landlordId });
    else if (kind === 'ADMIN') {
      await this.refundBooking(payment.booking.id, 'ADMIN', { actorId: adminId, reason: payment.refundReason ?? 'Retrying a refund that failed' });
    } else throw new BadRequestException('There is no failed refund to retry for this payment');
    return { status: 'REFUNDED' as const };
  }

  /// Super admin "Retry" on the Payouts screen. Goes through the same
  /// release as everything else (one at a time, and Paystack is asked first
  /// whether the transfer already went out), so pressing it twice — or
  /// while an automatic release runs — can't pay the landlord twice.
  async retryPayout(paymentId: string) {
    const payment = await this.prisma.payment.findUnique({
      where: { id: paymentId },
      include: { booking: { include: { property: true, tenant: true } } },
    });
    if (!payment || payment.purpose !== PaymentPurpose.RENTAL_BOOKING || !payment.booking) {
      throw new NotFoundException('Payout not found');
    }
    if (payment.status === PaymentStatus.RELEASED) return { status: 'ALREADY_PAID' as const };
    if (payment.status !== PaymentStatus.PAID_HELD) throw new BadRequestException('This payment is not waiting for a payout');
    const booking = payment.booking;
    const landlord = await this.prisma.user.findUniqueOrThrow({
      where: { id: booking.property.landlordId },
      include: { identityVerification: { select: { status: true } } },
    });
    if (!(await this.platform.payUnverifiedLandlords()) && landlord.identityVerification?.status !== VerificationStatus.APPROVED) {
      throw new BadRequestException(
        'This landlord is not verified and "Pay unverified landlords" is off. Verify them (or turn that switch on) and it is paid automatically.',
      );
    }
    const isLegacyShortlet = booking.property.category === PropertyCategory.SHORTLET && booking.status === BookingStatus.ACCEPTED;
    if (!isLegacyShortlet && booking.status !== BookingStatus.MOVED_IN && booking.status !== BookingStatus.PAID) {
      throw new BadRequestException("This rent is still held in escrow until the tenant moves in; it isn't owed to the landlord yet");
    }

    if (isLegacyShortlet) {
      // Also confirms the stay that the earlier failure left unconfirmed.
      await this.releaseShortletInstant(payment, booking);
    } else {
      await this.releasePaymentToRecipient(payment, {
        bankCode: landlord.bankCode,
        accountNumber: landlord.accountNumber,
        accountName: landlord.accountName,
        reason: `HomeServant payout — ${booking.property.title}`,
      });
      const naira = ((payment.amount - payment.platformFeeAmount) / 100).toLocaleString('en-NG', { maximumFractionDigits: 2 });
      await this.notifyAboutBooking(booking, 
        landlord.id,
        landlord.email,
        NotificationType.BOOKING_STATUS,
        'Your payout has been sent',
        `NGN ${naira} for ${booking.property.title} has been sent to your bank account.`,
      );
    }
    const after = await this.prisma.payment.findUniqueOrThrow({ where: { id: paymentId }, select: { status: true, payoutLastError: true } });
    if (after.status !== PaymentStatus.RELEASED) {
      throw new BadRequestException(after.payoutLastError ?? 'The payout did not go through');
    }
    return { status: 'PAID' as const };
  }

  /// For Platform Controls: how much is currently held.
  async heldPayoutStats(): Promise<{ count: number; totalKobo: number; landlords: number }> {
    const rows = await this.prisma.payment.findMany({
      where: { status: PaymentStatus.PAID_HELD, heldForVerificationAt: { not: null } },
      select: { amount: true, platformFeeAmount: true, booking: { select: { property: { select: { landlordId: true } } } } },
    });
    return {
      count: rows.length,
      totalKobo: rows.reduce((sum, r) => sum + r.amount - r.platformFeeAmount, 0),
      landlords: new Set(rows.map((r) => r.booking?.property.landlordId)).size,
    };
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
  /// The money has already moved by the time this runs, so a failure here
  /// is logged rather than failing the refund/rejection itself.
  private async postBookingSystemMessage(
    booking: { tenantId: string; propertyId: string; property: { landlordId: string } },
    body: string,
    createIfMissing: boolean,
  ): Promise<string | null> {
    try {
      return await this.chat.postBookingSystemMessage({
        tenantId: booking.tenantId,
        landlordId: booking.property.landlordId,
        propertyId: booking.propertyId,
        body,
        createIfMissing,
      });
    } catch (err) {
      this.logger.error(`Couldn't post the booking system message: ${err}`);
      return null;
    }
  }

  /// [notifyBoth] for a booking: its emails include the property's details.
  private notifyAboutBooking(
    booking: { property: EmailProperty },
    userId: string,
    email: string | undefined,
    type: NotificationType,
    title: string,
    body: string,
    threadId?: string,
  ): Promise<void> {
    return this.notifyBoth(userId, email, type, title, body, threadId, booking.property);
  }

  private async notifyBoth(
    userId: string,
    email: string | undefined,
    type: NotificationType,
    title: string,
    body: string,
    threadId?: string,
    property?: EmailProperty,
  ): Promise<void> {
    await this.notifications.create(userId, type, title, body, threadId);
    if (email) {
      // Booking emails carry the property's details, so it's clear which
      // listing they're about.
      const details = property ? propertyEmailDetails(property) : null;
      await this.mail.send(email, title, `<p>${escapeHtml(body)}</p>${details?.html ?? ''}`, body + (details?.text ?? ''));
    }
  }
}
