import { BookingStatus, PaymentPurpose, PaymentStatus, Prisma, PropertyCategory, VerificationStatus } from '@prisma/client';
import { PAYOUT_LOCK_MS, bookingStillRefundable } from './payment-rules';

/// Which payments the admin Payouts & Refunds screen lists: rent owed to a
/// landlord that hasn't gone out (held for verification, or a transfer
/// that failed, or failed/reversed at the bank later), refunds that failed,
/// and shortlets from before failures were recorded whose instant payout
/// failed and left the stay unconfirmed. Rent simply waiting in escrow for
/// a tenant to move in is not listed.
export function stuckPaymentsWhere(now = new Date()): Prisma.PaymentWhereInput {
  const legacyCutoff = new Date(now.getTime() - 30 * 60 * 1000);
  return {
    purpose: PaymentPurpose.RENTAL_BOOKING,
    status: PaymentStatus.PAID_HELD,
    OR: [
      { heldForVerificationAt: { not: null } },
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
/// FAILED, or READY once the verification rule no longer applies) and which
/// actions are allowed. [payUnverified] is Platform Controls' "Pay
/// unverified landlords".
export function toStuckPayment(p: StuckPaymentRow, payUnverified: boolean, now = new Date()) {
  const verified = p.recipient.identityVerification?.status === VerificationStatus.APPROVED;
  const waitingForVerification = !payUnverified && !verified;
  const isShortlet = p.booking?.property.category === PropertyCategory.SHORTLET;
  // Money still held for a tenant who hasn't moved in (or whose stay hasn't
  // started) can be refunded to them by an admin.
  const tenantRefundable = !!p.booking && bookingStillRefundable(p.booking, isShortlet, now);
  const shared = {
    paymentId: p.id,
    paidAt: p.paidAt,
    inProgress: !!p.moneyLockedAt && p.moneyLockedAt > new Date(now.getTime() - PAYOUT_LOCK_MS),
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
    };
  }
  const reason = waitingForVerification
    ? 'AWAITING_VERIFICATION'
    : !p.recipient.accountNumber
      ? 'NO_BANK_ACCOUNT'
      : p.payoutLastError || !p.heldForVerificationAt
        ? 'FAILED'
        : 'READY';
  return {
    kind: 'PAYOUT' as const,
    ...shared,
    amountKobo: p.amount - p.platformFeeAmount,
    heldSince: p.heldForVerificationAt ?? p.payoutLastAttemptAt ?? p.paidAt,
    reason,
    lastError: p.payoutLastError ?? (p.heldForVerificationAt ? null : "The instant payout failed (details weren't recorded at the time)"),
    attempts: p.payoutAttempts,
    lastAttemptAt: p.payoutLastAttemptAt,
    requestedBy: null,
    canRetry: !waitingForVerification && !!p.recipient.accountNumber,
    canRetryRefund: false,
    canRefundTenant: tenantRefundable,
  };
}
