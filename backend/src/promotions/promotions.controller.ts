import { Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { PromotionsService } from './promotions.service';

/// A landlord featuring their own listing — see PromotionsService.
@Controller('properties/:id/promotions')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.LANDLORD)
export class PromotionsController {
  constructor(private readonly promotions: PromotionsService) {}

  @Get('quote')
  quote(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.promotions.quote(id, user.sub);
  }

  /// Starts Paystack checkout; returns the page to pay on.
  @Post()
  start(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.promotions.start(id, user.sub);
  }

  @Get()
  history(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.promotions.history(id, user.sub);
  }
}
