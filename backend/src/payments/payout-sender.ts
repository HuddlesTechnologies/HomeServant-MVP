import { BadRequestException, InternalServerErrorException, Logger } from '@nestjs/common';
import { NotificationType, Payment, PaymentStatus, VerificationStatus } from '@prisma/client';
import { PaystackService } from '../paystack/paystack.service';
import { PlatformSettingsService } from '../platform-settings/platform-settings.service';
import { PrismaService } from '../prisma/prisma.service';
import { withMoneyLock } from './money-lock';
import { PaymentNotices } from './payment-notices';
import {
  CANCELLED_PAYOUT_ERROR,
  PAUSED_PAYOUT_ERROR,
  TRANSFER_OTP_ERROR,
  TRANSFER_OTP_STATUS,
  PayoutOutcome,
  RETRYABLE_TRANSFER_STATUSES,
  isLowBalanceError,
  lowBalanceMessage,
} from './payment-rules';

/// A landlord's or vendor's payout details.
export type PayoutAccount = { bankCode: string | null; accountNumber: string | null; accountName: string | null };

/// Sends held money to the landlord or vendor it's owed to, and holds rent
/// for landlords who must be verified first (Platform Controls).
export class PayoutSender {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly platform: PlatformSettingsService,
    private readonly notices: PaymentNotices,
    private readonly logger: Logger,
  ) {}

  /// Sends the recipient's share (amount - platformFeeAmount) and marks the
  /// payment RELEASED. It can never pay twice:
  ///   1. the money lock lets only one payout or refund run per payment;
  ///   2. Paystack is asked first whether the last transfer for this payment
  ///      exists. If it was sent (or is on its way) it's recorded as paid
  ///      and nothing is sent. A new reference is used only when Paystack
  ///      says the previous one failed or was reversed;
  ///   3. the reference is saved before sending, so a crash after Paystack
  ///      accepts it is caught by step 2 next time.
  /// Throws on failure, after saving the error on the payment for the admin
  /// Payouts screen. Pass [lockHeld] when the caller already holds the lock.
  async send(payment: Payment, opts: PayoutAccount & { reason: string }, lockHeld = false): Promise<void> {
    if (!lockHeld) {
      const now = await this.prisma.payment.findUnique({ where: { id: payment.id }, select: { status: true } });
      if (now?.status === PaymentStatus.RELEASED) return; // already paid
      return withMoneyLock(this.prisma, payment.id, () => this.send(payment, opts, true));
    }
    try {
      if (!opts.bankCode || !opts.accountNumber || !opts.accountName) {
        throw new InternalServerErrorException('No payout bank account on file for the recipient');
      }
      const current = await this.prisma.payment.findUniqueOrThrow({ where: { id: payment.id } });
      if (current.status !== PaymentStatus.PAID_HELD) throw new BadRequestException('This payment is no longer held');
      // An admin paused or cancelled it (Payouts & Refunds): nothing is sent.
      if (current.payoutCancelledAt) throw new BadRequestException(CANCELLED_PAYOUT_ERROR);
      if (current.payoutPausedAt) throw new BadRequestException(PAUSED_PAYOUT_ERROR);

      // Payments released before payoutReference existed used their own id
      // as the transfer reference.
      const lastReference = current.payoutReference ?? payment.id;
      const existing = await this.paystack.verifyTransfer(lastReference);
      // Still waiting for an OTP at Paystack: not paid, and sending again
      // could pay twice once it's confirmed.
      if (existing === TRANSFER_OTP_STATUS) throw new BadRequestException(TRANSFER_OTP_ERROR);
      if (existing !== 'not_found' && !RETRYABLE_TRANSFER_STATUSES.has(existing)) {
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

      // Payouts come out of HomeServant's Paystack balance. A payout it
      // can't cover isn't sent (or counted as an attempt). If the balance
      // can't be read, send anyway: Paystack refuses what it can't cover.
      const amountKobo = payment.amount - payment.platformFeeAmount;
      const available = await this.balanceKobo();
      if (available !== null && available < amountKobo) {
        throw new BadRequestException(lowBalanceMessage(available, amountKobo));
      }

      await this.prisma.payment.update({
        where: { id: payment.id },
        data: { payoutReference: reference, payoutAttempts: { increment: 1 }, payoutLastAttemptAt: new Date() },
      });
      let transfer: { status: string } | undefined;
      try {
        transfer = await this.paystack.initiateTransfer(amountKobo, recipientCode, opts.reason, reference);
      } catch (error) {
        if (isLowBalanceError((error as Error).message)) throw new BadRequestException(lowBalanceMessage(available, amountKobo));
        throw error;
      }
      // Accepted but held for an OTP: the money hasn't gone out, so it isn't
      // marked paid (and the landlord isn't told it was).
      if (transfer?.status?.toLowerCase() === TRANSFER_OTP_STATUS) {
        this.logger.error(`Payout ${payment.id}: Paystack is holding transfer ${reference} for an OTP; not marked as paid`);
        throw new BadRequestException(TRANSFER_OTP_ERROR);
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

  /// HomeServant's Paystack balance, or null if Paystack can't be asked.
  async balanceKobo(): Promise<number | null> {
    try {
      return await this.paystack.balanceKobo();
    } catch {
      return null;
    }
  }

  /// Paystack's `transfer.failed` / `transfer.reversed` webhook: the money
  /// never reached (or came back from) the landlord, so it's owed again and
  /// shows on the admin Payouts screen. A retry is safe: Paystack confirms
  /// that reference failed, so a fresh one is used.
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

  /// Pays [landlord] their rent now, or holds it (marked
  /// heldForVerificationAt) when "Pay unverified landlords" is off and they
  /// aren't verified. Never throws: a failed transfer returns 'failed' and
  /// waits on the admin Payouts screen, so the tenant's side (move-in,
  /// stay, renewal) always goes ahead. A payout an admin paused (or
  /// cancelled) isn't sent: it's marked as having come due and returns
  /// 'paused'.
  async releaseOrHold(
    payment: Payment,
    landlord: PayoutAccount & { id: string },
    reason: string,
    lockHeld = false,
  ): Promise<PayoutOutcome> {
    const flags = await this.prisma.payment.findUnique({
      where: { id: payment.id },
      select: { payoutPausedAt: true, payoutCancelledAt: true },
    });
    if (flags?.payoutPausedAt || flags?.payoutCancelledAt) {
      await this.prisma.payment.update({
        where: { id: payment.id },
        data: { payoutLastError: flags.payoutCancelledAt ? CANCELLED_PAYOUT_ERROR : PAUSED_PAYOUT_ERROR },
      });
      this.logger.log(`Payout for payment ${payment.id} not sent: ${flags.payoutCancelledAt ? 'cancelled' : 'paused'} by an admin`);
      return 'paused';
    }
    if (!(await this.platform.payUnverifiedLandlords())) {
      const verification = await this.prisma.identityVerification.findUnique({ where: { userId: landlord.id }, select: { status: true } });
      if (verification?.status !== VerificationStatus.APPROVED) {
        await this.prisma.payment.update({ where: { id: payment.id }, data: { heldForVerificationAt: new Date() } });
        this.logger.log(`Payout for payment ${payment.id} held until landlord ${landlord.id} is verified`);
        return 'held';
      }
    }
    try {
      await this.send(payment, { ...landlord, reason }, lockHeld);
      return 'released';
    } catch (err) {
      this.logger.error(`Payout for payment ${payment.id} failed: ${(err as Error).message}`);
      return 'failed';
    }
  }

  /// Sends every payout held for [landlordId]'s verification: called when
  /// they're verified, or for everyone when the rule is switched off. One
  /// that fails stays held (logged) for the next attempt. Returns how many
  /// were sent.
  async releaseHeldForLandlord(landlordId: string): Promise<number> {
    const landlord = await this.prisma.user.findUnique({
      where: { id: landlordId },
      select: { id: true, email: true, bankCode: true, accountNumber: true, accountName: true },
    });
    if (!landlord) return 0;
    const held = await this.prisma.payment.findMany({
      where: {
        status: PaymentStatus.PAID_HELD,
        heldForVerificationAt: { not: null },
        payoutPausedAt: null,
        payoutCancelledAt: null,
        booking: { property: { landlordId } },
      },
      include: { booking: { select: { property: { select: { title: true } } } } },
    });
    let released = 0;
    let totalKobo = 0;
    for (const payment of held) {
      try {
        await this.send(payment, {
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
      await this.notices.notifyBoth(
        landlord.id,
        landlord.email,
        NotificationType.BOOKING_STATUS,
        'Your held payouts have been released',
        `${released} payout${released === 1 ? '' : 's'} (NGN ${naira}) held by HomeServant ${released === 1 ? 'has' : 'have'} been sent to your bank account.`,
      );
    }
    return released;
  }

  /// [releaseHeldForLandlord] for every landlord with held payouts: used
  /// when "Pay unverified landlords" is switched back on.
  async releaseAllHeld(): Promise<number> {
    const rows = await this.prisma.payment.findMany({
      where: { status: PaymentStatus.PAID_HELD, heldForVerificationAt: { not: null }, payoutPausedAt: null, payoutCancelledAt: null },
      select: { booking: { select: { property: { select: { landlordId: true } } } } },
    });
    const landlordIds = [...new Set(rows.map((r) => r.booking?.property.landlordId).filter((id): id is string => !!id))];
    let released = 0;
    for (const id of landlordIds) released += await this.releaseHeldForLandlord(id);
    return released;
  }

  /// For Platform Controls: how much is held for verification right now.
  async heldStats(): Promise<{ count: number; totalKobo: number; landlords: number }> {
    const rows = await this.prisma.payment.findMany({
      where: { status: PaymentStatus.PAID_HELD, heldForVerificationAt: { not: null }, payoutCancelledAt: null },
      select: { amount: true, platformFeeAmount: true, booking: { select: { property: { select: { landlordId: true } } } } },
    });
    return {
      count: rows.length,
      totalKobo: rows.reduce((sum, r) => sum + r.amount - r.platformFeeAmount, 0),
      landlords: new Set(rows.map((r) => r.booking?.property.landlordId)).size,
    };
  }
}
