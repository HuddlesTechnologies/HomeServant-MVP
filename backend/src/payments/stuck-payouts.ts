import { BookingStatus, PaymentPurpose, PaymentStatus, Prisma, PropertyCategory, VerificationStatus } from '@prisma/client';
import { CANCELLED_PAYOUT_ERROR, PAUSED_PAYOUT_ERROR, PAYOUT_LOCK_MS, bookingStillRefundable } from './payment-rules';

/// Which payments the admin Payouts & Refunds screen lists: rent owed to a
/// landlord that hasn't gone out (held for verification, or a transfer
/// that failed, or failed/reversed at the bank later), refunds that failed,
/// and shortlets from before failures were recorded whose instant payout
/// failed and left the stay unconfirmed, and payouts an admin paused. Rent
/// simply waiting in escrow for a tenant to move in is not listed, nor is a
/// payout an admin cancelled.
export function stuckPaymentsWhere(now = new Date()): Prisma.PaymentWhereInput {
  const legacyCutoff = new Date(now.getTime() - 30 * 60 * 1000);
  return {
    purpose: PaymentPurpose.RENTAL_BOOKING,
    status: PaymentStatus.PAID_HELD,
    payoutCancelledAt: null,
    OR: [
      { heldForVerificationAt: { not: null } },
      { payoutPausedAt: { not: null } },
      { payoutLastError: { not: null } },
      { refundLastError: { not: null } },
      { paidAt: { lt: legacyCutoff }, booking: { status: BookingStatus.ACCEPTED, property: { category: PropertyCategory.SHORTLET } } },
    ],
  };
}

export const stuckPaymentInclude = {
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
} satisfies Prisma.PaymentInclude;

type StuckPaymentRow = Prisma.PaymentGetPayload<{ include: typeof stuckPaymentInclude }>;

/// One row of the Payouts & Refunds screen: a failed refund to retry, or a
/// payout with why it's stuck (AWAITING_VERIFICATION, NO_BANK_ACCOUNT,
/// FAILED, READY once the verification rule no longer applies, or PAUSED by
/// an admin) and which actions are allowed. [payUnverified] is Platform Controls' "Pay
/// unverified landlords".
export function toStuckPayment(p: StuckPaymentRow, payUnverified: boolean, now = new Date()) {
  const verified = p.recipient.identityVerification?.status === VerificationStatus.APPROVED;
  const waitingForVerification = !payUnverified && !verified;
  const isShortlet = p.booking?.property.category === PropertyCategory.SHORTLET;
  // Money still held for a tenant who hasn't moved in (or whose stay hasn't
  // started) can be refunded to them by an admin.
  const tenantRefundable = !!p.booking && bookingStillRefundable(p.booking, isShortlet, now);
  const inProgress = !!p.moneyLockedAt && p.moneyLockedAt > new Date(now.getTime() - PAYOUT_LOCK_MS);
  const paused = !!p.payoutPausedAt;
  const shared = {
    paymentId: p.id,
    paidAt: p.paidAt,
    inProgress,
    pausedAt: p.payoutPausedAt,
    pauseReason: p.payoutPauseReason,
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
  if (p.refundLastError) {
    return {
      kind: 'REFUND' as const,
      ...shared,
      amountKobo: p.refundRequestedAmount ?? p.amount,
      heldSince: p.refundLastAttemptAt ?? p.paidAt,
      reason: 'REFUND_FAILED',
      lastError: p.refundLastError,
      requestedBy: p.refundRequestedBy,
      attempts: 0,
      lastAttemptAt: p.refundLastAttemptAt,
      canRetry: false,
      canRetryRefund: tenantRefundable,
      canRefundTenant: false,
      canPause: false,
      canResume: false,
      canCancel: false,
    };
  }
  // It came due while paused: not a failed transfer, just not sent yet.
  const cameDueWhilePaused = p.payoutLastError === PAUSED_PAYOUT_ERROR || p.payoutLastError === CANCELLED_PAYOUT_ERROR;
  const reason = paused
    ? 'PAUSED'
    : waitingForVerification
      ? 'AWAITING_VERIFICATION'
      : !p.recipient.accountNumber
        ? 'NO_BANK_ACCOUNT'
        : cameDueWhilePaused
          ? 'READY'
          : p.payoutLastError || !p.heldForVerificationAt
            ? 'FAILED'
            : 'READY';
  return {
    kind: 'PAYOUT' as const,
    ...shared,
    amountKobo: p.amount - p.platformFeeAmount,
    heldSince: p.payoutPausedAt ?? p.heldForVerificationAt ?? p.payoutLastAttemptAt ?? p.paidAt,
    reason,
    lastError: cameDueWhilePaused
      ? 'Came due while the payout was paused'
      : (p.payoutLastError ?? (p.heldForVerificationAt || paused ? null : "The instant payout failed (details weren't recorded at the time)")),
    attempts: p.payoutAttempts,
    lastAttemptAt: p.payoutLastAttemptAt,
    requestedBy: null,
    canRetry: !paused && !waitingForVerification && !!p.recipient.accountNumber,
    canRetryRefund: false,
    canRefundTenant: tenantRefundable,
    canPause: !paused && !inProgress,
    canResume: paused,
    canCancel: !inProgress,
  };
}
