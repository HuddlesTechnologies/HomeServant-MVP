import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { FulfillmentMethod, NotificationType } from '@prisma/client';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { VendorsService } from '../vendors/vendors.service';
import { CreateOrderDto } from './dto/create-order.dto';
import { RespondOrderItemDto } from './dto/respond-order-item.dto';

const orderInclude = {
  items: { include: { product: { select: { id: true, name: true, imageUrls: true } }, vendor: { select: { id: true, userId: true, businessName: true } } } },
} as const;

@Injectable()
export class MarketplaceOrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly vendors: VendorsService,
    private readonly notifications: NotificationsService,
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

    return this.prisma.$transaction(async (tx) => {
      for (const item of dto.items) {
        const result = await tx.product.updateMany({
          where: { id: item.productId, stock: { gte: item.quantity } },
          data: { stock: { decrement: item.quantity } },
        });
        if (result.count === 0) {
          throw new BadRequestException(`Not enough stock for ${byId.get(item.productId)!.name} — try again`);
        }
      }

      const order = await tx.marketplaceOrder.create({
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

      return order;
    });
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

  async respondToItem(userId: string, itemId: string, dto: RespondOrderItemDto) {
    const vendor = await this.vendors.requireOwn(userId);
    const item = await this.assertItemOwnership(itemId, vendor.id);
    const updated = await this.prisma.marketplaceOrderItem.update({ where: { id: itemId }, data: { status: dto.status } });
    const order = await this.prisma.marketplaceOrder.findUniqueOrThrow({ where: { id: item.orderId }, select: { buyerId: true } });
    await this.notifications.create(
      order.buyerId,
      NotificationType.MARKETPLACE_ORDER_STATUS,
      dto.status === 'COMPLETED' ? 'Order completed' : dto.status === 'CANCELLED' ? 'Order cancelled' : 'Order updated',
      `Your order for ${item.productName} from ${vendor.businessName} is now ${dto.status.toLowerCase()}.`,
    );
    return updated;
  }

  async markItemRead(userId: string, itemId: string): Promise<void> {
    const vendor = await this.vendors.requireOwn(userId);
    await this.assertItemOwnership(itemId, vendor.id);
    await this.prisma.marketplaceOrderItem.update({ where: { id: itemId }, data: { notificationRead: true } });
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
