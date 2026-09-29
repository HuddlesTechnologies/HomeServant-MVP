import { BadRequestException, ForbiddenException, Logger, NotFoundException } from '@nestjs/common';
import { BookingStatus, NotificationType, Payment, PaymentStatus, PropertyCategory } from '@prisma/client';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { withMoneyLock } from './money-lock';
import { PaymentNotices } from './payment-notices';
import { REFUND_FEE_BPS, bookingStillRefundable, fee } from './payment-rules';

/// Who asked for a booking refund. TENANT: before move-in, keeps the 0.2%
/// fee. LANDLORD: rejects the booking before move-in, full refund. ADMIN:
/// full refund, before move-in or before a shortlet stay starts.
export type RefundRequester = 'TENANT' | 'LANDLORD' | 'ADMIN';

/// Gives a booking's held rent back to the tenant.
export class BookingRefunds {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly notices: PaymentNotices,
    private readonly logger: Logger,
  ) {}

  /// The one refund flow for every requester, so the same guarantees apply:
  ///  - the booking and its held payment are re-checked inside the money
  ///    lock, so a refund can't overlap a move-in payout, another refund or
  ///    a retry (whoever comes second is told it's in progress or done);
  ///  - Paystack is asked first whether the charge was already refunded
  ///    ([refundHeldPayment]), so it's never refunded twice;
  ///  - afterwards the booking is REFUNDED (DECLINED when the landlord
  ///    rejected it) and the payment REFUNDED, which every path checks.
  async refundBooking(
    bookingId: string,
    kind: RefundRequester,
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

    const refundAmountKobo = kind === 'TENANT' ? payment.amount - fee(payment.amount, REFUND_FEE_BPS) : payment.amount;
    const updated = await withMoneyLock(this.prisma, payment.id, async () => {
      // Re-check now that nothing else can move this money.
      const now = await this.prisma.booking.findUniqueOrThrow({ where: { id: bookingId } });
      const stillHeld = await this.prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
      if (stillHeld.status !== PaymentStatus.PAID_HELD) throw new BadRequestException('This payment has already been refunded or paid out');
      if (!bookingStillRefundable(now, isShortlet)) {
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
      await this.notices.postBookingSystemMessage(
        booking,
        `Refund initiated by the tenant for ${title}. Further messaging is no longer available unless the tenant books and pays again.`,
        false,
      );
      await this.notices.notifyAboutBooking(booking, booking.tenantId, booking.tenant.email, NotificationType.BOOKING_STATUS, 'Refund issued', `Your payment for ${title} has been refunded.`);
      if (landlord) {
        await this.notices.notifyBoth(
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
      const threadId = await this.notices.postBookingSystemMessage(
        booking,
        `The landlord rejected this booking for ${title} and the tenant has been fully refunded. Further messaging is no longer available unless the tenant books and pays again.`,
        true,
      );
      await this.notices.notifyAboutBooking(
        booking,
        booking.tenantId,
        booking.tenant.email,
        NotificationType.BOOKING_STATUS,
        'Booking rejected',
        `The landlord was unable to proceed with your booking for ${title}. You've been fully refunded.`,
        threadId ?? undefined,
      );
    } else {
      const threadId = await this.notices.postBookingSystemMessage(
        booking,
        `HomeServant refunded the tenant in full for ${title}. Reason: ${opts.reason}. Further messaging is no longer available unless the tenant books and pays again.`,
        true,
      );
      await this.notices.notifyAboutBooking(
        booking,
        booking.tenantId,
        booking.tenant.email,
        NotificationType.BOOKING_STATUS,
        'You have been refunded',
        `HomeServant has refunded your payment for ${title} in full. Reason: ${opts.reason}`,
        threadId ?? undefined,
      );
      if (landlord) {
        await this.notices.notifyBoth(
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
  async refundHeldPayment(payment: Payment, amountKobo: number, requestedBy: string): Promise<void> {
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
}
