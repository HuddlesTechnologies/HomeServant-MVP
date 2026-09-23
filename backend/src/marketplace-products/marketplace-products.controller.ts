import { Body, Controller, Delete, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CreateProductDto } from './dto/create-product.dto';
import { QueryProductsDto } from './dto/query-products.dto';
import { UpdateProductDto } from './dto/update-product.dto';
import { MarketplaceProductsService } from './marketplace-products.service';

@Controller('marketplace/products')
export class MarketplaceProductsController {
  constructor(private readonly products: MarketplaceProductsService) {}

  /// Public — the customer-facing browse feed.
  @Get()
  findMany(@Query() query: QueryProductsDto) {
    return this.products.findMany(query);
  }

  /// Before `:id` — otherwise "mine" would be parsed as a product id.
  @Get('mine')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.VENDOR)
  findMine(@CurrentUser() user: AuthenticatedUser) {
    return this.products.findMine(user.sub);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.products.findOne(id);
  }

  @Post()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.VENDOR)
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateProductDto) {
    return this.products.create(user.sub, dto);
  }

  @Patch(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.VENDOR)
  update(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string, @Body() dto: UpdateProductDto) {
    return this.products.update(user.sub, id, dto);
  }

  @Delete(':id')
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles(UserRole.VENDOR)
  remove(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.products.remove(user.sub, id);
  }
}
