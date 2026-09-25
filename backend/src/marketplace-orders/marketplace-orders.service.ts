import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from '@nestjs/common';
import { FulfillmentMethod, NotificationType, OrderItemStatus } from '@prisma/client';
import { DELIVERY_PROVIDER } from '../delivery/delivery.constants';
import { DeliveryProvider } from '../delivery/delivery-provider.interface';
import { NotificationsService } from '../notifications/notifications.service';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';
import { VendorsService } from '../vendors/vendors.service';
import { CreateOrderDto } from './dto/create-order.dto';
import { RespondOrderItemDto } from './dto/respond-order-item.dto';
import { ShipOrderItemDto } from './dto/ship-order-item.dto';

const orderInclude = {
  items: {
    include: {
      product: { select: { id: true, name: true, imageUrls: true } },
      vendor: { select: { id: true, userId: true, businessName: true } },
      payment: { select: { status: true } },
    },
  },
} as const;

@Injectable()
export class MarketplaceOrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly vendors: VendorsService,
    private readonly notifications: NotificationsService,
    private readonly payments: PaymentsService,
    @Inject(DELIVERY_PROVIDER) private readonly delivery: DeliveryProvider,
  ) {}

  /// Buyer info comes from the authenticated account's own profile, not a
  /// separate checkout form — mirrors how the Flutter client already
  /// worked before this had a real backend (see marketplace_home_screen's
  /// old `_placeOrder`). Stock is checked and decremented atomically per
  /// item (a conditional `updateMany` guarded by `stock >= quantity`, not
  /// a plain read-then-write) so two concurrent buyers can't both
  /// successfully oversell the last unit.
  async create(buyerId: string, dto: CreateOrderDto) {
    const buyer = await this.prisma.user.findUniqueOrThrow({ where: { id: buyerId } });
    if (!buyer.phoneNumber) {
      throw new BadRequestException('Add a phone number to your profile before checking out');
    }
    const needsAddress = dto.items.some((i) => i.fulfillment === FulfillmentMethod.DELIVERY);
    if (needsAddress && !buyer.houseAddress) {
      throw new BadRequestException('Add a house address to your profile before checking out for delivery');
    }

    const productIds = dto.items.map((i) => i.productId);
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds } },
      include: { vendor: { select: { id: true, isActive: true } } },
    });
    const byId = new Map(products.map((p) => [p.id, p]));

    for (const item of dto.items) {
      const product = byId.get(item.productId);
      if (!product || !product.isAvailable || !product.vendor.isActive) {
        throw new NotFoundException(`Product ${item.productId} is no longer available`);
      }
      if (!product.fulfillmentOptions.includes(item.fulfillment)) {
        throw new BadRequestException(`${product.name} doesn't support ${item.fulfillment.toLowerCase()}`);
      }
      if (product.stock < item.quantity) {
        throw new BadRequestException(`Not enough stock for ${product.name}`);
      }
    }

    const order = await this.prisma.$transaction(async (tx) => {
      for (const item of dto.items) {
        const result = await tx.product.updateMany({
          where: { id: item.productId, stock: { gte: item.quantity } },
          data: { stock: { decrement: item.quantity } },
        });
        if (result.count === 0) {
          throw new BadRequestException(`Not enough stock for ${byId.get(item.productId)!.name} — try again`);
        }
      }

      return tx.marketplaceOrder.create({
        data: {
          buyerId,
          paymentMethod: dto.paymentMethod,
          customerName: buyer.fullName || 'Customer',
          customerPhone: buyer.phoneNumber!,
          customerAddress: buyer.houseAddress ?? '',
          items: {
            create: dto.items.map((item) => {
              const product = byId.get(item.productId)!;
              return {
                productId: product.id,
                vendorId: product.vendorId,
                productName: product.name,
                unitPrice: product.price,
                quantity: item.quantity,
                fulfillment: item.fulfillment,
              };
            }),
          },
        },
        include: orderInclude,
      });
    });

    // Charging happens *after* the order/stock-decrement transaction
    // commits — a Paystack call has no place inside a DB transaction (it
    // would hold the transaction open across a network round-trip).
    return this.chargeOrder(order, buyerId, buyer.email);
  }

  /// Charges the buyer right after the order+items above are committed —
  /// one Paystack transaction per item (Payment.orderItemId is unique, so
  /// a multi-vendor order is necessarily one charge per item, never one
  /// combined charge). A per-item failure to reach Paystack doesn't fail
  /// the whole order (it already exists in the DB); see
  /// PaymentsService.initiateOrderItemCharges.
  private async chargeOrder(order: { items: { id: string; productName: string; unitPrice: number; quantity: number; vendorId: string; vendor: { userId: string } }[] }, buyerId: string, buyerEmail: string) {
    const results = await this.payments.initiateOrderItemCharges(
      order.items.map((item) => ({
        id: item.id,
        productName: item.productName,
        unitPrice: item.unitPrice,
        quantity: item.quantity,
        vendorId: item.vendorId,
        vendorUserId: item.vendor.userId,
      })),
      buyerId,
      buyerEmail,
    );
    return { ...order, payments: results };
  }

  findMine(buyerId: string) {
    return this.prisma.marketplaceOrder.findMany({
      where: { buyerId },
      include: orderInclude,
      orderBy: { createdAt: 'desc' },
    });
  }

  /// Flattened order-item view for a vendor — mirrors the app's old
  /// `vendorOrderEntries()`, but scoped by a real vendorId instead of a
  /// business-name string match.
  async findForVendor(userId: string) {
    const vendor = await this.vendors.requireOwn(userId);
    return this.prisma.marketplaceOrderItem.findMany({
      where: { vendorId: vendor.id },
      include: {
        product: { select: { id: true, name: true, imageUrls: true } },
        order: { select: { id: true, createdAt: true, paymentMethod: true, customerName: true, customerPhone: true, customerAddress: true, buyerId: true } },
      },
      orderBy: { order: { createdAt: 'desc' } },
    });
  }

  /// A vendor can still CANCEL an item (e.g. out of stock, can't fulfil),
  /// but can no longer mark one COMPLETED directly — now that payments are
  /// held in escrow, only the buyer's own confirm-received action (see
  /// confirmReceived) can release funds and mark an item COMPLETED.
  /// Cancelling an item whose payment is already held triggers a full
  /// refund to the buyer (no platform fee withheld — that 0.2% cut is
  /// specific to the rental pre-move-in refund path, not marketplace
  /// cancellations).
  async respondToItem(userId: string, itemId: string, dto: RespondOrderItemDto) {
    if (dto.status === 'COMPLETED') {
      throw new BadRequestException('Items are marked completed automatically when the buyer confirms receipt');
    }
    const vendor = await this.vendors.requireOwn(userId);
    const item = await this.assertItemOwnership(itemId, vendor.id);
    if (item.status !== OrderItemStatus.PENDING) {
      throw new BadRequestException('This item has already been resolved');
    }

    await this.payments.refundOrderItemIfHeld(itemId);
    const updated = await this.prisma.marketplaceOrderItem.update({ where: { id: itemId }, data: { status: dto.status } });
    const order = await this.prisma.marketplaceOrder.findUniqueOrThrow({ where: { id: item.orderId }, select: { buyerId: true } });
    await this.notifications.create(
      order.buyerId,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Order cancelled',
      `Your order for ${item.productName} from ${vendor.businessName} was cancelled and refunded if it was already paid.`,
    );
    return updated;
  }

  /// `POST /marketplace-orders/items/:id/confirm-received` — buyer-only,
  /// must own the order. Releases the vendor's 95% share and marks the
  /// item COMPLETED.
  confirmReceived(userId: string, itemId: string) {
    return this.payments.confirmOrderItemReceived(itemId, userId);
  }

  async markItemRead(userId: string, itemId: string): Promise<void> {
    const vendor = await this.vendors.requireOwn(userId);
    await this.assertItemOwnership(itemId, vendor.id);
    await this.prisma.marketplaceOrderItem.update({ where: { id: itemId }, data: { notificationRead: true } });
  }

  /// Vendor action for a DELIVERY-fulfillment item: books a shipment with
  /// whichever DeliveryProvider is configured (see
  /// src/delivery/delivery.module.ts) and stores the returned
  /// shipmentId/trackingNumber on the item. Best-effort scaffolding — see
  /// delivery-provider.interface.ts's doc comment for the caveat that the
  /// real GIG Logistics contract behind this is unverified.
  async shipItem(userId: string, itemId: string, dto: ShipOrderItemDto) {
    const vendor = await this.vendors.requireOwn(userId);
    const item = await this.assertItemOwnership(itemId, vendor.id);

    if (item.fulfillment !== FulfillmentMethod.DELIVERY) {
      throw new BadRequestException('Only delivery-fulfillment items can be shipped');
    }
    if (item.shipmentId) {
      throw new BadRequestException('This item has already been shipped');
    }

    const order = await this.prisma.marketplaceOrder.findUniqueOrThrow({
      where: { id: item.orderId },
      select: { buyerId: true, customerAddress: true },
    });
    if (!order.customerAddress) {
      throw new BadRequestException('This order has no delivery address on file');
    }

    const shipment = await this.delivery.createShipment({
      pickupAddress: dto.pickupAddress ?? `${vendor.businessName}, ${vendor.state}`,
      dropoffAddress: order.customerAddress,
      itemDescription: `${item.quantity} x ${item.productName}`,
      weightKg: dto.weightKg,
    });

    const updated = await this.prisma.marketplaceOrderItem.update({
      where: { id: itemId },
      data: { shipmentId: shipment.shipmentId, trackingNumber: shipment.trackingNumber, shippedAt: new Date() },
    });

    await this.notifications.create(
      order.buyerId,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      'Order shipped',
      `Your order for ${item.productName} from ${vendor.businessName} has shipped. Tracking number: ${shipment.trackingNumber}.`,
    );

    return updated;
  }

  /// Buyer-facing read: looks up live tracking for an item the buyer's
  /// own order contains, once the vendor has shipped it.
  async getItemTracking(userId: string, itemId: string) {
    const item = await this.prisma.marketplaceOrderItem.findUnique({
      where: { id: itemId },
      include: { order: { select: { buyerId: true } } },
    });
    if (!item) throw new NotFoundException('Order item not found');
    if (item.order.buyerId !== userId) {
      throw new ForbiddenException('You do not own this order');
    }
    if (!item.shipmentId) {
      throw new BadRequestException('This item has not been shipped yet');
    }

    return this.delivery.trackShipment(item.shipmentId);
  }

  private async assertItemOwnership(itemId: string, vendorId: string) {
    const item = await this.prisma.marketplaceOrderItem.findUnique({ where: { id: itemId } });
    if (!item) throw new NotFoundException('Order item not found');
    if (item.vendorId !== vendorId) {
      throw new ForbiddenException('You do not own this order item');
    }
    return item;
  }
}
