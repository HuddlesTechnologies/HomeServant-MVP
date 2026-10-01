import { BadRequestException, Logger, NotFoundException } from '@nestjs/common';
import { NotificationType, OrderItemStatus, PaymentPurpose, PaymentStatus } from '@prisma/client';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { PaymentNotices } from './payment-notices';
import { KOBO_PER_NAIRA, PAYOUT_LOCK_MS, PLATFORM_FEE_BPS, fee, generateReference } from './payment-rules';

/// How long a buyer has to pay for a marketplace order before it's
/// cancelled and its stock put back.
export const MARKETPLACE_CHECKOUT_MINUTES = 60;

/// Paystack charge states meaning the buyer didn't (and won't) pay, so an
/// expired order can be cancelled. Anything else (success, ongoing,
/// pending, processing, queued) is left alone.
const UNPAID_CHARGE_STATUSES = new Set(['not_found', 'abandoned', 'failed', 'reversed']);

export type CheckoutItem = { id: string; productName: string; unitPrice: number; quantity: number; vendorUserId: string };

/// A marketplace order is paid in one Paystack checkout, however many
/// items or vendors it has. Each item still gets its own Payment (linked by
/// Payment.chargeReference to the order's charge), so each is held, paid
/// out to its vendor and refunded on its own, exactly as before.
export class MarketplaceCheckout {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly notices: PaymentNotices,
    private readonly logger: Logger,
  ) {}

  /// Starts the order's one charge for every item. Nothing is paid until
  /// Paystack confirms it ([onChargeSuccess]). If the checkout can't be
  /// started, the order is cancelled, its stock put back, and this throws.
  async start(orderId: string, items: CheckoutItem[], buyerId: string, buyerEmail: string) {
    const reference = generateReference('mkto');
    const totalKobo = items.reduce((sum, i) => sum + i.unitPrice * i.quantity * KOBO_PER_NAIRA, 0);
    await this.prisma.$transaction([
      ...items.map((item) => {
        const amountKobo = item.unitPrice * item.quantity * KOBO_PER_NAIRA;
        return this.prisma.payment.create({
          data: {
            purpose: PaymentPurpose.MARKETPLACE_ORDER_ITEM,
            orderItemId: item.id,
            payerId: buyerId,
            recipientUserId: item.vendorUserId,
            amount: amountKobo,
            platformFeeAmount: fee(amountKobo, PLATFORM_FEE_BPS),
            paystackReference: generateReference('mkti'),
            chargeReference: reference,
            status: PaymentStatus.INITIATED,
          },
        });
      }),
      this.prisma.marketplaceOrder.update({
        where: { id: orderId },
        data: { paystackReference: reference, paymentExpiresAt: new Date(Date.now() + MARKETPLACE_CHECKOUT_MINUTES * 60_000) },
      }),
    ]);

    try {
      const init = await this.paystack.initializeTransaction(buyerEmail, totalKobo, reference, { orderId, purpose: 'MARKETPLACE_ORDER' });
      await this.prisma.marketplaceOrder.update({ where: { id: orderId }, data: { authorizationUrl: init.authorizationUrl } });
      return { reference: init.reference, authorizationUrl: init.authorizationUrl };
    } catch (err) {
      this.logger.error(`Could not start the Paystack checkout for order ${orderId}: ${(err as Error).message}`);
      await this.cancelUnpaid(reference);
      throw new BadRequestException("Couldn't start the payment, so the order was cancelled and nothing was charged. Try again.");
    }
  }

  /// Paystack's `charge.success` for an order's charge: every item still
  /// waiting is now paid and held. Returns the newly paid payments (empty
  /// if [reference] isn't an order charge, or was already handled). A
  /// charge that arrives after the order was cancelled for not being paid
  /// in time is refunded in full.
  async onChargeSuccess(reference: string) {
    const order = await this.prisma.marketplaceOrder.findUnique({ where: { paystackReference: reference }, select: { id: true, buyerId: true } });
    if (!order) return null;
    const { count } = await this.prisma.payment.updateMany({
      where: { chargeReference: reference, status: PaymentStatus.INITIATED },
      data: { status: PaymentStatus.PAID_HELD, paidAt: new Date() },
    });
    if (count > 0) {
      return this.prisma.payment.findMany({ where: { chargeReference: reference, status: PaymentStatus.PAID_HELD, paidAt: { not: null } } });
    }
    await this.refundLatePayment(reference, order.buyerId);
    return [];
  }

  /// The buyer came back from Paystack (`?reference=` on the URL): confirm
  /// the order's charge straight away instead of waiting for the webhook.
  /// Only the buyer can, and only a charge Paystack says succeeded counts.
  async confirm(reference: string, buyerId: string, handleChargeSuccess: (reference: string) => Promise<void>): Promise<{ paid: boolean }> {
    const order = await this.prisma.marketplaceOrder.findUnique({ where: { paystackReference: reference }, select: { buyerId: true } });
    if (!order || order.buyerId !== buyerId) throw new NotFoundException('Order not found');
    const waiting = await this.prisma.payment.count({ where: { chargeReference: reference, status: PaymentStatus.INITIATED } });
    if (waiting === 0) {
      const paid = await this.prisma.payment.count({ where: { chargeReference: reference, status: { in: [PaymentStatus.PAID_HELD, PaymentStatus.RELEASED] } } });
      return { paid: paid > 0 };
    }
    if ((await this.paystack.verifyCharge(reference)) !== 'success') return { paid: false };
    await handleChargeSuccess(reference);
    return { paid: true };
  }

  /// Cancels every order whose checkout ran out of time unpaid, after
  /// asking Paystack: a charge that did succeed is processed instead, and
  /// one still in progress (e.g. a bank transfer clearing) is left for
  /// next time. Returns how many orders were cancelled.
  async expireUnpaid(handleChargeSuccess: (reference: string) => Promise<void>, now = new Date()): Promise<number> {
    const orders = await this.prisma.marketplaceOrder.findMany({
      where: {
        paystackReference: { not: null },
        paymentExpiresAt: { lt: now },
        items: { some: { payment: { status: PaymentStatus.INITIATED } } },
      },
      select: { paystackReference: true },
    });
    let cancelled = 0;
    for (const { paystackReference } of orders) {
      const reference = paystackReference!;
      try {
        const status = await this.paystack.verifyCharge(reference);
        if (status === 'success') {
          await handleChargeSuccess(reference);
        } else if (UNPAID_CHARGE_STATUSES.has(status)) {
          if (await this.cancelUnpaid(reference)) cancelled++;
        }
      } catch (err) {
        this.logger.warn(`Couldn't check unpaid order charge ${reference}: ${(err as Error).message}`);
      }
    }
    return cancelled;
  }

  /// Marks the order's still-unpaid payments FAILED, cancels those items and
  /// puts their stock back, then tells the buyer. Only payments this call
  /// flips are touched, so a charge confirmed meanwhile is never undone.
  private async cancelUnpaid(reference: string): Promise<boolean> {
    const waiting = await this.prisma.payment.findMany({
      where: { chargeReference: reference, status: PaymentStatus.INITIATED },
      select: { id: true, orderItemId: true },
    });
    let cancelledItems: { productName: string }[] = [];
    let buyerId: string | null = null;
    await this.prisma.$transaction(async (tx) => {
      for (const p of waiting) {
        const flipped = await tx.payment.updateMany({ where: { id: p.id, status: PaymentStatus.INITIATED }, data: { status: PaymentStatus.FAILED } });
        if (flipped.count === 0 || !p.orderItemId) continue;
        const item = await tx.marketplaceOrderItem.update({
          where: { id: p.orderItemId },
          data: { status: OrderItemStatus.CANCELLED },
          include: { order: { select: { buyerId: true } } },
        });
        await tx.product.update({ where: { id: item.productId }, data: { stock: { increment: item.quantity } } });
        cancelledItems = [...cancelledItems, { productName: item.productName }];
        buyerId = item.order.buyerId;
      }
    });
    if (cancelledItems.length === 0 || !buyerId) return false;
    const names = cancelledItems.map((i) => i.productName).join(', ');
    await this.notices.notifyBoth(
      buyerId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Order cancelled: not paid',
      `Your order for ${names} wasn't paid, so it was cancelled and nothing was charged. You can order again any time.`,
    );
    return true;
  }

  /// Money for an order that was already cancelled as unpaid (the buyer
  /// paid after it expired): refunded in full, once. Under the order's
  /// refund lock, so two deliveries of the same webhook can't both refund.
  private async refundLatePayment(reference: string, buyerId: string): Promise<void> {
    const failed = await this.prisma.payment.findMany({ where: { chargeReference: reference, status: PaymentStatus.FAILED } });
    if (failed.length === 0) return;
    const claimed = await this.prisma.marketplaceOrder.updateMany({
      where: { paystackReference: reference, OR: [{ refundLockedAt: null }, { refundLockedAt: { lt: new Date(Date.now() - PAYOUT_LOCK_MS) } }] },
      data: { refundLockedAt: new Date() },
    });
    if (claimed.count === 0) return; // another delivery is refunding it
    const totalKobo = failed.reduce((sum, p) => sum + p.amount, 0);
    try {
      if ((await this.paystack.refundedSoFar(reference)) === 0) {
        await this.paystack.refundTransaction(reference);
      }
      await this.prisma.payment.updateMany({
        where: { id: { in: failed.map((p) => p.id) }, status: PaymentStatus.FAILED },
        data: { status: PaymentStatus.REFUNDED, refundedAt: new Date(), refundRequestedBy: 'MARKETPLACE', platformFeeAmount: 0 },
      });
    } finally {
      await this.prisma.marketplaceOrder.updateMany({ where: { paystackReference: reference }, data: { refundLockedAt: null } });
    }
    this.logger.warn(`Order charge ${reference} paid after it was cancelled as unpaid; refunded in full`);
    await this.notices.notifyBoth(
      buyerId,
      undefined,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Payment refunded',
      `Your payment of NGN ${(totalKobo / 100).toLocaleString('en-NG')} arrived after the order had been cancelled for not being paid in time, so it has been refunded in full.`,
    );
  }
}
