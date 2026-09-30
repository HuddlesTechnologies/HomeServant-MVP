import { Cron, CronExpression } from '@nestjs/schedule';
import { BadRequestException, ConflictException, ForbiddenException, Injectable, InternalServerErrorException, Logger, NotFoundException } from '@nestjs/common';
import { BookingStatus, NotificationType, OrderItemStatus, Payment, PaymentPlan, PaymentPurpose, PaymentStatus, PriceUnit, PropertyCategory, VerificationStatus } from '@prisma/client';
import { ChatService } from '../chat/chat.service';
import { formatRent } from '../common/format-rent';
import { EmailProperty } from '../common/property-email';
import { assertRentalAvailable } from '../common/rental-availability';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PaystackService } from '../paystack/paystack.service';
import { PlatformSettingsService } from '../platform-settings/platform-settings.service';
import { PrismaService } from '../prisma/prisma.service';
import { BookingRefunds } from './booking-refunds';
import { withMoneyLock } from './money-lock';
import { PaymentNotices } from './payment-notices';
import {
  KOBO_PER_NAIRA,
  MONTHLY_PAY_WINDOW_DAYS,
  MS_PER_DAY,
  PLATFORM_FEE_BPS,
  RENEWAL_WINDOW_DAYS,
  addDays,
  addMonths,
  fee,
  generateReference,
  isLowBalanceError,
  landlordPayoutMessage,
  minDate,
} from './payment-rules';
import { PayoutSender } from './payout-sender';
import { stuckPaymentInclude, stuckPaymentsWhere, toStuckPayment } from './stuck-payouts';

export { LOW_BALANCE_ERROR, isLowBalanceError } from './payment-rules';

/// HomeServant's escrow: every payment is charged in full, held in
/// HomeServant's own Paystack balance, and later either sent to the
/// landlord or vendor (their share, minus HomeServant's 5%) or refunded to
/// the payer. Paystack Split Payments are never used. Rentals, shortlets
/// and marketplace orders all go through here, so each money rule lives in
/// one place.
///
/// This class runs each flow (charge, confirm, move in, renew, refund,
/// retry). The pieces those flows share live beside it: PayoutSender (send
/// a payout, never twice), BookingRefunds (the one refund flow),
/// withMoneyLock (one money action per payment at a time), PaymentNotices
/// (notifications, emails and chat notices) and payment-rules.ts (fees,
/// dates and wording).
@Injectable()
export class PaymentsService {
  private readonly logger = new Logger('Payments');
  private readonly notices: PaymentNotices;
  private readonly payouts: PayoutSender;
  private readonly refunds: BookingRefunds;

  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    notifications: NotificationsService,
    mail: MailService,
    chat: ChatService,
    private readonly platform: PlatformSettingsService,
  ) {
    this.notices = new PaymentNotices(notifications, mail, chat, this.logger);
    this.payouts = new PayoutSender(prisma, paystack, platform, this.notices, this.logger);
    this.refunds = new BookingRefunds(prisma, paystack, this.notices, this.logger);
  }

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
      const platformFeeKobo = fee(amountKobo, PLATFORM_FEE_BPS);
      const reference = generateReference('mkt');

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
  /// vendor can't mark an item COMPLETED themselves.
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

    await this.payouts.send(item.payment, {
      bankCode: item.vendor.bankCode,
      accountNumber: item.vendor.accountNumber,
      accountName: item.vendor.accountName,
      reason: `HomeServant marketplace payout — ${item.productName}`,
    });

    const updated = await this.prisma.marketplaceOrderItem.update({ where: { id: itemId }, data: { status: OrderItemStatus.COMPLETED } });

    await this.notices.notifyBoth(
      item.vendor.userId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Payment released',
      `The buyer confirmed receipt of ${item.productName} — your payout has been sent.`,
    );
    await this.notices.notifyBoth(
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
    await withMoneyLock(this.prisma, payment.id, async () => {
      await this.refunds.refundHeldPayment(payment, payment.amount, 'MARKETPLACE');
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

    await this.payouts.send(item.payment, {
      bankCode: item.vendor.bankCode,
      accountNumber: item.vendor.accountNumber,
      accountName: item.vendor.accountName,
      reason: `HomeServant marketplace payout (auto-released) — ${item.productName}`,
    });
    await this.prisma.marketplaceOrderItem.update({ where: { id: itemId }, data: { status: OrderItemStatus.COMPLETED } });

    await this.notices.notifyBoth(
      item.vendor.userId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Payment released',
      `Your payout for ${item.productName} was released automatically 7 days after ${item.fulfillment === 'DELIVERY' ? 'shipping' : 'payment'} — the buyer never confirmed receipt.`,
    );
    await this.notices.notifyBoth(
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
    const platformFeeKobo = fee(amountKobo, PLATFORM_FEE_BPS);
    const reference = generateReference('rent');

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
    const { outcome, updatedBooking } = await withMoneyLock(this.prisma, payment.id, async () => {
      const now = await this.prisma.booking.findUniqueOrThrow({ where: { id: bookingId } });
      if (now.status !== BookingStatus.INSPECTION_CONFIRMED) throw new BadRequestException('This booking is not awaiting move-in');
      const held = await this.prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
      const outcome = await this.payouts.releaseOrHold(held, landlord, `HomeServant rent release — ${booking.property.title}`, true);

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

    await this.notices.notifyAboutBooking(
      booking,
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Welcome home!',
      `You've moved into ${booking.property.title}. Your tenancy agreement is ready in your booking history.`,
    );
    await this.notices.notifyAboutBooking(
      booking,
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Tenant moved in',
      landlordPayoutMessage(
        outcome,
        `Your tenant has moved into ${booking.property.title}`,
        `Your tenant has moved into ${booking.property.title} and your payout has been released.`,
      ),
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
    return this.refunds.refundBooking(bookingId, 'TENANT', { actorId: tenantId });
  }

  /// `POST /bookings/:id/reject` — the landlord's own distinct
  /// outright-rejection lever, separate from declining an inspection date
  /// (BookingsService.respondToInspection) — full refund, **no** platform
  /// fee withheld (unlike the tenant-initiated `refundBookingBeforeMoveIn`,
  /// which keeps the 0.2% cut), since this is the landlord's decision, not
  /// the tenant's.
  async rejectBookingByLandlord(bookingId: string, landlordId: string) {
    return this.refunds.refundBooking(bookingId, 'LANDLORD', { actorId: landlordId });
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
    return this.refunds.refundBooking(payment.bookingId, 'ADMIN', { actorId: adminId, reason: trimmed });
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
    await this.notices.notifyBoth(
      item.order.buyerId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Payment held',
      `Your payment for ${item.productName} is confirmed and held until you confirm delivery.`,
    );
    await this.notices.notifyBoth(
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
    const threadId = await this.notices.postBookingSystemMessage(
      booking,
      `Payment confirmed for ${booking.property.title}. The money is held by HomeServant until the tenant moves in. You can now message each other to arrange the inspection.`,
      true,
    );
    await this.notices.notifyAboutBooking(
      booking,
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Payment confirmed',
      `Your payment for ${booking.property.title} is confirmed and held. Message the landlord, book an inspection whenever you're ready, or request a refund, from your booking history.`,
      threadId ?? undefined,
    );
    await this.notices.notifyAboutBooking(
      booking,
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

    const outcome = await this.payouts.releaseOrHold(payment, landlord, `HomeServant shortlet release — ${booking.property.title}`);

    const leaseStart = booking.requestedDate;
    const leaseEnd = addDays(leaseStart, booking.nights);
    await this.prisma.booking.update({
      where: { id: booking.id },
      data: { status: BookingStatus.PAID, leaseStartDate: leaseStart, leaseEndDate: leaseEnd },
    });

    const threadId = await this.notices.postBookingSystemMessage(
      booking,
      `Payment confirmed for the stay at ${booking.property.title}. You can now message each other about check-in.`,
      true,
    );
    await this.notices.notifyAboutBooking(
      booking,
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Booking confirmed',
      `Your shortlet stay at ${booking.property.title} is confirmed and paid. Message the landlord about check-in from here.`,
      threadId ?? undefined,
    );
    await this.notices.notifyAboutBooking(
      booking,
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Shortlet booked and paid',
      landlordPayoutMessage(
        outcome,
        `${booking.property.title} was booked and paid`,
        `${booking.property.title} was booked and your payout has been released.`,
      ),
      threadId ?? undefined,
    );
  }

  /// A monthly tenant's payment for the next month cleared: it goes
  /// straight to the landlord (the tenant already lives there, like a
  /// renewal), and the rent is paid a month further.
  private async releaseMonthlyInstallment(
    payment: Payment,
    booking: { id: string; rentPaidThrough: Date | null; leaseEndDate: Date | null; property: EmailProperty & { landlordId: string; title: string }; tenantId: string; tenant: { email: string } },
  ): Promise<void> {
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: booking.property.landlordId } });
    const outcome = await this.payouts.releaseOrHold(payment, landlord, `HomeServant monthly rent — ${booking.property.title}`);
    const paidThrough = minDate(addMonths(booking.rentPaidThrough!, 1), booking.leaseEndDate!);
    await this.prisma.booking.update({
      where: { id: booking.id },
      data: { rentPaidThrough: paidThrough, monthlyReminderSentFor: null, monthlyOverdueNotifiedFor: null },
    });
    const until = paidThrough.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' });
    const naira = `₦${Math.round(payment.amount / KOBO_PER_NAIRA).toLocaleString('en-US')}`;
    await this.notices.notifyAboutBooking(
      booking,
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Monthly rent paid',
      `Thanks — your rent for ${booking.property.title} is paid until ${until}.`,
    );
    await this.notices.notifyAboutBooking(
      booking,
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Monthly rent received',
      landlordPayoutMessage(
        outcome,
        `Your tenant paid ${naira} rent for ${booking.property.title} (paid until ${until})`,
        `Your tenant paid ${naira} rent for ${booking.property.title} (paid until ${until}) and your payout has been released.`,
      ),
    );
  }

  /// A renewal payment cleared: like a monthly payment, it goes straight to
  /// the landlord since the tenant already lives there. Extends the lease
  /// from its current end date (not from today), makes the rent paid the
  /// booking's price and the tenancy agreement's rent, and resets the
  /// reminder fields so the next term's 30/15/0-day reminders fire.
  private async releaseRenewal(payment: Payment, booking: { id: string; propertyId: string; leaseEndDate: Date | null; paymentPlan?: PaymentPlan; property: EmailProperty & { landlordId: string; title: string; rentDurationMonths: number | null }; tenantId: string; tenant: { email: string } }): Promise<void> {
    if (!booking.leaseEndDate || !booking.property.rentDurationMonths) {
      this.logger.error(`Renewal payment ${payment.id} succeeded but booking ${booking.id} is missing leaseEndDate/rentDurationMonths`);
      return;
    }
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: booking.property.landlordId } });

    const outcome = await this.payouts.releaseOrHold(payment, landlord, `HomeServant rent renewal release — ${booking.property.title}`);

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

    await this.notices.notifyAboutBooking(
      booking,
      booking.tenantId,
      booking.tenant.email,
      NotificationType.BOOKING_STATUS,
      'Lease renewed',
      `Your lease for ${booking.property.title} has been renewed until ${newLeaseEnd.toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })} at ${formatRent(rentPaid, priceUnit)}. Your tenancy agreement has been updated.`,
    );
    await this.notices.notifyAboutBooking(
      booking,
      landlord.id,
      landlord.email,
      NotificationType.BOOKING_STATUS,
      'Renewal paid',
      landlordPayoutMessage(
        outcome,
        `Your tenant renewed their lease for ${booking.property.title}`,
        `Your tenant renewed their lease for ${booking.property.title} and your payout has been released.`,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Payouts (see PayoutSender)
  // ---------------------------------------------------------------------

  /// Paystack's `transfer.failed` / `transfer.reversed` webhook; see
  /// PayoutSender.handleTransferFailed.
  handleTransferFailed(reference: string, outcome: 'failed' | 'reversed', reason?: string): Promise<void> {
    return this.payouts.handleTransferFailed(reference, outcome, reason);
  }

  /// Sends every payout held until [landlordId] was verified. Returns how
  /// many were sent.
  releaseHeldPayoutsForLandlord(landlordId: string): Promise<number> {
    return this.payouts.releaseHeldForLandlord(landlordId);
  }

  /// Sends every held payout, for every landlord: used when "Pay
  /// unverified landlords" is switched back on.
  releaseAllHeldPayouts(): Promise<number> {
    return this.payouts.releaseAllHeld();
  }

  // ---------------------------------------------------------------------
  // Admin: Payouts needing attention
  // ---------------------------------------------------------------------

  /// Rows for the admin Payouts & Refunds screen, oldest first; see
  /// stuck-payouts.ts for what's listed and why.
  async stuckPayouts() {
    const rows = await this.prisma.payment.findMany({
      where: stuckPaymentsWhere(),
      include: stuckPaymentInclude,
      orderBy: { paidAt: 'asc' },
      take: 300,
    });
    const payUnverified = await this.platform.payUnverifiedLandlords();
    return rows.map((p) => toStuckPayment(p, payUnverified));
  }

  /// 'test' or 'live' (or 'unknown'): which Paystack balance payouts come
  /// from; see PaystackService.mode.
  paystackMode(): 'test' | 'live' | 'unknown' {
    return this.paystack.mode ?? 'unknown';
  }

  /// HomeServant's Paystack balance, for the admin Payouts screen (null if
  /// Paystack can't be asked right now).
  paystackBalanceKobo(): Promise<number | null> {
    return this.payouts.balanceKobo();
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
      where: {
        purpose: PaymentPurpose.RENTAL_BOOKING,
        status: PaymentStatus.PAID_HELD,
        payoutLastError: { not: null },
        payoutPausedAt: null,
        payoutCancelledAt: null,
      },
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
    if (kind === 'TENANT') await this.refunds.refundBooking(payment.booking.id, 'TENANT', { actorId: payment.booking.tenantId });
    else if (kind === 'LANDLORD') await this.refunds.refundBooking(payment.booking.id, 'LANDLORD', { actorId: payment.booking.property.landlordId });
    else if (kind === 'ADMIN') {
      await this.refunds.refundBooking(payment.booking.id, 'ADMIN', { actorId: adminId, reason: payment.refundReason ?? 'Retrying a refund that failed' });
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
    if (payment.payoutCancelledAt) throw new BadRequestException('This payout was cancelled');
    if (payment.payoutPausedAt) throw new BadRequestException('This payout is paused. Resume it first.');
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
      await this.payouts.send(payment, {
        bankCode: landlord.bankCode,
        accountNumber: landlord.accountNumber,
        accountName: landlord.accountName,
        reason: `HomeServant payout — ${booking.property.title}`,
      });
      const naira = ((payment.amount - payment.platformFeeAmount) / 100).toLocaleString('en-NG', { maximumFractionDigits: 2 });
      await this.notices.notifyAboutBooking(
      booking,
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

  /// Payouts & Refunds "Pause": stops this landlord payout from going out —
  /// automatically (move-in, verification, low-balance retries) or by Retry
  /// — until it's resumed. Taken under the money lock, so it can't land in
  /// the middle of a transfer. [reason] is for other admins only.
  async pausePayout(paymentId: string, adminId: string, reason: string) {
    await this.loadRentalPayout(paymentId);
    await withMoneyLock(this.prisma, paymentId, async () => {
      const current = await this.prisma.payment.findUniqueOrThrow({ where: { id: paymentId } });
      if (current.payoutCancelledAt) throw new BadRequestException('This payout was cancelled');
      if (current.payoutPausedAt) return;
      await this.prisma.payment.update({
        where: { id: paymentId },
        data: { payoutPausedAt: new Date(), payoutPausedById: adminId, payoutPauseReason: reason.trim() },
      });
    });
    this.logger.log(`Payout ${paymentId} paused by admin ${adminId}`);
    return { status: 'PAUSED' as const };
  }

  /// Payouts & Refunds "Resume": lifts a pause, then sends the payout if
  /// it's owed now (the landlord is payable and the tenant has moved in /
  /// the stay is confirmed). If it isn't owed yet, or the transfer fails,
  /// it simply stays on the Payouts screen as before: [sent] says which.
  async resumePayout(paymentId: string, adminId: string) {
    const payment = await this.loadRentalPayout(paymentId);
    if (!payment.payoutPausedAt) return { status: 'RESUMED' as const, sent: false, message: null };
    await withMoneyLock(this.prisma, paymentId, () =>
      this.prisma.payment.update({
        where: { id: paymentId },
        data: { payoutPausedAt: null, payoutPausedById: null, payoutPauseReason: null },
      }),
    );
    this.logger.log(`Payout ${paymentId} resumed by admin ${adminId}`);
    // Only one that came due while paused (or was already owed) is sent.
    const owed = !!payment.payoutLastError || !!payment.heldForVerificationAt;
    if (!owed) return { status: 'RESUMED' as const, sent: false, message: null };
    try {
      await this.retryPayout(paymentId);
      return { status: 'RESUMED' as const, sent: true, message: null };
    } catch (err) {
      return { status: 'RESUMED' as const, sent: false, message: (err as Error).message };
    }
  }

  /// Payouts & Refunds "Cancel payout": the landlord is never sent this
  /// money. It stays held by HomeServant (the payment stays PAID_HELD), so
  /// the tenant can still be refunded from it where the refund rules allow;
  /// it no longer shows on the Payouts screen. The landlord is told, with
  /// [reason].
  async cancelPayout(paymentId: string, adminId: string, reason: string) {
    const payment = await this.loadRentalPayout(paymentId);
    const trimmed = reason.trim();
    if (trimmed.length < 10) throw new BadRequestException('Give a reason (at least 10 characters); the landlord sees it');
    if (payment.payoutCancelledAt) return { status: 'CANCELLED' as const };
    await withMoneyLock(this.prisma, paymentId, () =>
      this.prisma.payment.update({
        where: { id: paymentId },
        data: {
          payoutCancelledAt: new Date(),
          payoutCancelledById: adminId,
          payoutCancelReason: trimmed,
          heldForVerificationAt: null,
          payoutLastError: null,
        },
      }),
    );
    this.logger.warn(`Payout ${paymentId} cancelled by admin ${adminId}: ${trimmed}`);
    const booking = payment.booking;
    const landlord = await this.prisma.user.findUnique({ where: { id: booking.property.landlordId }, select: { id: true, email: true } });
    if (landlord) {
      const naira = ((payment.amount - payment.platformFeeAmount) / 100).toLocaleString('en-NG', { maximumFractionDigits: 2 });
      await this.notices.notifyAboutBooking(
        booking,
        landlord.id,
        landlord.email,
        NotificationType.BOOKING_STATUS,
        'Your payout was cancelled',
        `HomeServant has cancelled your payout of NGN ${naira} for ${booking.property.title}. Reason: ${trimmed}. Contact support if you have questions.`,
      );
    }
    return { status: 'CANCELLED' as const };
  }

  /// A rent payment still held in escrow, with its booking and property.
  private async loadRentalPayout(paymentId: string) {
    const payment = await this.prisma.payment.findUnique({
      where: { id: paymentId },
      include: { booking: { include: { property: true } } },
    });
    if (!payment?.booking || payment.purpose !== PaymentPurpose.RENTAL_BOOKING) throw new NotFoundException('Payout not found');
    if (payment.status === PaymentStatus.RELEASED) throw new BadRequestException('This payout has already been sent');
    if (payment.status !== PaymentStatus.PAID_HELD) throw new BadRequestException('This payment is not waiting for a payout');
    return { ...payment, booking: payment.booking };
  }

  /// For Platform Controls: how much is currently held.
  heldPayoutStats(): Promise<{ count: number; totalKobo: number; landlords: number }> {
    return this.payouts.heldStats();
  }
}
