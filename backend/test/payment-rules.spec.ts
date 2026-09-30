import { BookingStatus } from '@prisma/client';
import { bookingStillRefundable, fee, landlordPayoutMessage, PLATFORM_FEE_BPS, REFUND_FEE_BPS } from '../src/payments/payment-rules';

describe('payment rules', () => {
  it('works out fees in whole kobo', () => {
    expect(fee(100000, PLATFORM_FEE_BPS)).toBe(5000); // 5%
    expect(fee(100000, REFUND_FEE_BPS)).toBe(200); // 0.2%
    expect(fee(333, PLATFORM_FEE_BPS)).toBe(17); // 16.65 rounds to 17
  });

  it('tells the landlord what happened to their payout', () => {
    const msg = (outcome: 'released' | 'held' | 'failed') => landlordPayoutMessage(outcome, 'Your tenant moved in', 'Your tenant moved in and your payout has been released.');
    expect(msg('released')).toBe('Your tenant moved in and your payout has been released.');
    expect(msg('held')).toMatch(/^Your tenant moved in\. HomeServant is holding your payout until your identity is verified/);
    expect(msg('failed')).toMatch(/^Your tenant moved in\. Your payout is delayed/);
  });

  it('refunds a rental only before move-in, and a shortlet only before the stay starts', () => {
    const now = new Date('2026-09-01T12:00:00Z');
    const rental = (status: BookingStatus) => bookingStillRefundable({ status, leaseStartDate: null }, false, now);
    expect(rental(BookingStatus.PAID_AWAITING_INSPECTION)).toBe(true);
    expect(rental(BookingStatus.INSPECTION_CONFIRMED)).toBe(true);
    expect(rental(BookingStatus.MOVED_IN)).toBe(false);

    const shortlet = (status: BookingStatus, leaseStartDate: Date | null) => bookingStillRefundable({ status, leaseStartDate }, true, now);
    expect(shortlet(BookingStatus.ACCEPTED, null)).toBe(true);
    expect(shortlet(BookingStatus.PAID, new Date('2026-09-05'))).toBe(true);
    expect(shortlet(BookingStatus.PAID, new Date('2026-08-30'))).toBe(false);
  });
});
