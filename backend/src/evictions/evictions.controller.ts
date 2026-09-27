import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { AdminLevel, UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { MinAdminLevel } from '../common/decorators/min-admin-level.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MustChangePasswordGuard } from '../common/guards/must-change-password.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CreateEvictionDto, EvictionResponseDto, ReviewEvictionDto } from './dto/eviction.dto';
import { EvictionsService } from './evictions.service';

@Controller('evictions')
@UseGuards(JwtAuthGuard, RolesGuard)
export class EvictionsController {
  constructor(private readonly evictions: EvictionsService) {}

  @Post()
  @Roles(UserRole.LANDLORD)
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateEvictionDto) {
    return this.evictions.create(user.sub, dto.bookingId, dto.reason);
  }

  @Get('mine')
  @Roles(UserRole.LANDLORD, UserRole.TENANT)
  mine(@CurrentUser() user: AuthenticatedUser) {
    return this.evictions.findMine(user.sub);
  }

  @Post(':id/cancel')
  @Roles(UserRole.LANDLORD)
  cancel(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.evictions.cancel(user.sub, id);
  }

  @Post(':id/respond')
  @Roles(UserRole.TENANT)
  respond(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string, @Body() dto: EvictionResponseDto) {
    return this.evictions.respond(user.sub, id, dto.response);
  }
}

/// Reviewing evictions is SUPER_ADMIN-only: approving one ends a real
/// person's tenancy.
@Controller('admin/evictions')
@UseGuards(JwtAuthGuard, RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
@Roles(UserRole.ADMIN)
@MinAdminLevel(AdminLevel.SUPER_ADMIN)
export class AdminEvictionsController {
  constructor(private readonly evictions: EvictionsService) {}

  @Get()
  findAll(@Query('status') status?: string) {
    return this.evictions.findForAdmin(status);
  }

  @Get('pending-count')
  async pendingCount() {
    return { count: await this.evictions.pendingCount() };
  }

  @Post(':id/review')
  review(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string, @Body() dto: ReviewEvictionDto) {
    return this.evictions.review(user.sub, id, dto.decision, dto.note);
  }
}
