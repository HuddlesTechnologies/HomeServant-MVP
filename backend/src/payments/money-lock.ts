import { BadRequestException, ConflictException } from '@nestjs/common';
import { PaymentStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { PAYOUT_LOCK_MS } from './payment-rules';

/// Runs [fn] while holding [paymentId]'s money lock, so only one payout or
/// refund can move a payment's money at a time: a payment can never be
/// paid out and refunded, or refunded twice. The lock is a timestamp on the
/// payment, claimed with a conditional update so two callers can't both
/// get it; one older than PAYOUT_LOCK_MS is treated as abandoned.
///
/// Throws if the payment is no longer held, or if another action holds the
/// lock.
export async function withMoneyLock<T>(prisma: PrismaService, paymentId: string, fn: () => Promise<T>): Promise<T> {
  const claimed = await prisma.payment.updateMany({
    where: {
      id: paymentId,
      status: PaymentStatus.PAID_HELD,
      OR: [{ moneyLockedAt: null }, { moneyLockedAt: { lt: new Date(Date.now() - PAYOUT_LOCK_MS) } }],
    },
    data: { moneyLockedAt: new Date() },
  });
  if (claimed.count === 0) {
    const current = await prisma.payment.findUnique({ where: { id: paymentId }, select: { status: true } });
    if (current?.status === PaymentStatus.REFUNDED) throw new BadRequestException('This payment has already been refunded');
    if (current?.status === PaymentStatus.RELEASED) throw new BadRequestException('This payment has already been paid out');
    throw new ConflictException('Another payment action is in progress for this booking. Try again in a moment.');
  }
  try {
    return await fn();
  } finally {
    await prisma.payment.update({ where: { id: paymentId }, data: { moneyLockedAt: null } });
  }
}
