import { randomBytes } from 'crypto';
import { BookingStatus } from '@prisma/client';

/// Amounts are stored in whole naira (Property.price, Product.price) but
/// Paystack works in kobo, so every amount is multiplied by this once,
/// before it reaches Paystack.
export const KOBO_PER_NAIRA = 100;

/// HomeServant's cut on a normal release (marketplace, rental move-in,
/// renewal, monthly rent, shortlet), in basis points: 500 = 5%.
export const PLATFORM_FEE_BPS = 500;

/// The cut kept when a tenant refunds a rental before moving in: 0.2%.
/// Paystack also keeps its own processing fee on a refund, so the tenant
/// bears both without this code computing Paystack's fee.
export const REFUND_FEE_BPS = 20;

const BPS_DENOMINATOR = 10000;

/// [bps] basis points of [amountKobo], rounded to the nearest kobo.
export function fee(amountKobo: number, bps: number): number {
  return Math.round((amountKobo * bps) / BPS_DENOMINATOR);
}

/// A unique Paystack charge reference, e.g. "rent_1727000000000_a1b2c3d4e5f6".
export function generateReference(prefix: string): string {
  return `${prefix}_${Date.now()}_${randomBytes(6).toString('hex')}`;
}

/// A lease can be renewed from this many days before it ends.
export const RENEWAL_WINDOW_DAYS = 30;

/// A monthly tenant can pay the next month from this many days before it's
/// due.
export const MONTHLY_PAY_WINDOW_DAYS = 7;

export const MS_PER_DAY = 24 * 60 * 60 * 1000;

export function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * MS_PER_DAY);
}

export function addMonths(date: Date, months: number): Date {
  const d = new Date(date);
  d.setMonth(d.getMonth() + months);
  return d;
}

export function minDate(a: Date, b: Date): Date {
  return a.getTime() <= b.getTime() ? a : b;
}

/// Non-shortlet rental statuses between payment and move-in: the money is
/// held, and the tenant can refund or the landlord can reject.
export const PRE_MOVE_IN_STATUSES: BookingStatus[] = [
  BookingStatus.PAID_AWAITING_INSPECTION,
  BookingStatus.INSPECTION_PROPOSED,
  BookingStatus.INSPECTION_CONFIRMED,
];

/// Whether a booking's held rent can still go back to the tenant: a rental
/// the tenant hasn't moved into, or a shortlet whose stay hasn't started.
export function bookingStillRefundable(
  booking: { status: BookingStatus; leaseStartDate: Date | null },
  isShortlet: boolean,
  now = new Date(),
): boolean {
  if (!isShortlet) return PRE_MOVE_IN_STATUSES.includes(booking.status);
  return (
    booking.status === BookingStatus.ACCEPTED ||
    (booking.status === BookingStatus.PAID && !!booking.leaseStartDate && booking.leaseStartDate > now)
  );
}

/// How long a money lock may be held before it's treated as abandoned (the
/// process holding it crashed).
export const PAYOUT_LOCK_MS = 10 * 60 * 1000;

/// Paystack transfer states meaning the money did NOT go out, so a new
/// attempt with a fresh reference is safe. Anything else (success, pending,
/// processing, otp, queued, received) counts as sent.
export const RETRYABLE_TRANSFER_STATUSES = new Set(['failed', 'reversed', 'abandoned', 'rejected']);

/// Start of the error recorded when a payout can't be sent because
/// HomeServant's Paystack balance is lower than it. Such payouts are
/// retried automatically (PaymentsService.retryLowBalancePayouts).
export const LOW_BALANCE_ERROR = "HomeServant's Paystack balance is too low";

/// True for our low-balance error, or Paystack's own wording for a transfer
/// bigger than the balance ("Your balance is not enough to fulfil this
/// request", "Insufficient balance").
export function isLowBalanceError(message: string | null | undefined): boolean {
  return !!message && (message.startsWith(LOW_BALANCE_ERROR) || /balance.*(not enough|insufficient)|insufficient.*balance/i.test(message));
}

/// The error kept on a payout the balance can't cover, shown to admins.
export function lowBalanceMessage(availableKobo: number | null, neededKobo: number): string {
  const naira = (kobo: number) => `NGN ${(kobo / 100).toLocaleString('en-NG', { maximumFractionDigits: 2 })}`;
  return (
    `${LOW_BALANCE_ERROR} to send this payout (${availableKobo === null ? 'balance unknown' : `${naira(availableKobo)} available`}, ` +
    `${naira(neededKobo)} needed). Payouts are sent from the Paystack balance: fund it, or have Paystack keep collected ` +
    `payments there instead of settling them to the bank. It's retried automatically every 30 minutes.`
  );
}

/// What happened to a landlord's payout: sent, held until they're
/// verified, or failed and waiting for a retry.
export type PayoutOutcome = 'released' | 'held' | 'failed';

const HELD_PAYOUT_LINE =
  "HomeServant is holding your payout until your identity is verified. Open your Profile and tap \"Get verified\"; it's released automatically once you are.";
const DELAYED_PAYOUT_LINE =
  "Your payout is delayed by a problem sending it to your bank. HomeServant has been alerted and will send it shortly; check your bank details in the app.";

/// The landlord's notification text after rent is paid: [event] ("Your
/// tenant has moved into X") plus what happened to their payout, or
/// [whenReleased] when it was sent.
export function landlordPayoutMessage(outcome: PayoutOutcome, event: string, whenReleased: string): string {
  if (outcome === 'held') return `${event}. ${HELD_PAYOUT_LINE}`;
  if (outcome === 'failed') return `${event}. ${DELAYED_PAYOUT_LINE}`;
  return whenReleased;
}
