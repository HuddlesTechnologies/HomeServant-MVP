import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CreateOrderDto } from './dto/create-order.dto';
import { RespondOrderItemDto } from './dto/respond-order-item.dto';
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
  @Roles(UserRole.VENDOR)
  findForVendor(@CurrentUser() user: AuthenticatedUser) {
    return this.orders.findForVendor(user.sub);
  }

  @Patch('items/:itemId/status')
  @UseGuards(RolesGuard)
  @Roles(UserRole.VENDOR)
  respondToItem(@CurrentUser() user: AuthenticatedUser, @Param('itemId') itemId: string, @Body() dto: RespondOrderItemDto) {
    return this.orders.respondToItem(user.sub, itemId, dto);
  }

  @Patch('items/:itemId/read')
  @UseGuards(RolesGuard)
  @Roles(UserRole.VENDOR)
  @HttpCode(HttpStatus.NO_CONTENT)
  async markItemRead(@CurrentUser() user: AuthenticatedUser, @Param('itemId') itemId: string): Promise<void> {
    await this.orders.markItemRead(user.sub, itemId);
  }
}
