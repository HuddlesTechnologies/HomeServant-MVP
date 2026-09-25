import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CreateOrderDto } from './dto/create-order.dto';
import { RespondOrderItemDto } from './dto/respond-order-item.dto';
import { ShipOrderItemDto } from './dto/ship-order-item.dto';
import { MarketplaceOrdersService } from './marketplace-orders.service';

@Controller('marketplace/orders')
@UseGuards(JwtAuthGuard)
export class MarketplaceOrdersController {
  constructor(private readonly orders: MarketplaceOrdersService) {}

  @Post()
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateOrderDto) {
    return this.orders.create(user.sub, dto);
  }

  @Get('mine')
  findMine(@CurrentUser() user: AuthenticatedUser) {
    return this.orders.findMine(user.sub);
  }

  @Get('vendor')
  @UseGuards(RolesGuard)
  @Roles(UserRole.TENANT, UserRole.VENDOR)
  findForVendor(@CurrentUser() user: AuthenticatedUser) {
    return this.orders.findForVendor(user.sub);
  }

  @Patch('items/:itemId/status')
  @UseGuards(RolesGuard)
  @Roles(UserRole.TENANT, UserRole.VENDOR)
  respondToItem(@CurrentUser() user: AuthenticatedUser, @Param('itemId') itemId: string, @Body() dto: RespondOrderItemDto) {
    return this.orders.respondToItem(user.sub, itemId, dto);
  }

  /// Buyer-only — releases the vendor's escrowed payment and marks the
  /// item COMPLETED. No @Roles restriction: the buyer can be any role
  /// (tenant/landlord/vendor alike can all shop the marketplace).
  @Post('items/:itemId/confirm-received')
  confirmReceived(@CurrentUser() user: AuthenticatedUser, @Param('itemId') itemId: string) {
    return this.orders.confirmReceived(user.sub, itemId);
  }

  @Patch('items/:itemId/read')
  @UseGuards(RolesGuard)
  @Roles(UserRole.TENANT, UserRole.VENDOR)
  @HttpCode(HttpStatus.NO_CONTENT)
  async markItemRead(@CurrentUser() user: AuthenticatedUser, @Param('itemId') itemId: string): Promise<void> {
    await this.orders.markItemRead(user.sub, itemId);
  }

  /// Vendor marks a DELIVERY-fulfillment item as shipped — books a
  /// shipment with the configured DeliveryProvider (best-effort GIG
  /// Logistics scaffolding, see src/delivery/) and stores the returned
  /// shipmentId/trackingNumber.
  @Patch('items/:itemId/ship')
  @UseGuards(RolesGuard)
  @Roles(UserRole.TENANT, UserRole.VENDOR)
  shipItem(@CurrentUser() user: AuthenticatedUser, @Param('itemId') itemId: string, @Body() dto: ShipOrderItemDto) {
    return this.orders.shipItem(user.sub, itemId, dto);
  }

  /// Buyer-facing tracking lookup for an order item that's been shipped.
  @Get('items/:itemId/tracking')
  getItemTracking(@CurrentUser() user: AuthenticatedUser, @Param('itemId') itemId: string) {
    return this.orders.getItemTracking(user.sub, itemId);
  }
}
