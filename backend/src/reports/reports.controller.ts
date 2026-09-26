import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MustChangePasswordGuard } from '../common/guards/must-change-password.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { CreateReportDto } from './dto/create-report.dto';
import { SetReportStatusDto } from './dto/set-report-status.dto';
import { TransferReportDto } from './dto/transfer-report.dto';
import { ReportsService } from './reports.service';

@Controller('reports')
@UseGuards(JwtAuthGuard)
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  /// Any authenticated role — eligibility (actually rented/purchased the
  /// target) is enforced in ReportsService.create, not by role.
  // Moderate throttling: user-generated/spammable but authenticated, so a
  // looser cap than the unauthenticated auth endpoints is fine.
  @Throttle({ default: { limit: 20, ttl: 60000 } })
  @Post()
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateReportDto) {
    return this.reports.create(user.sub, dto);
  }

  @Get('mine')
  mine(@CurrentUser() user: AuthenticatedUser) {
    return this.reports.findMine(user.sub);
  }

  @Get()
  @UseGuards(RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
  @Roles(UserRole.ADMIN)
  findAll(@Query('status') status?: 'OPEN' | 'IN_PROGRESS' | 'RESOLVED', @Query('page') page?: string, @Query('pageSize') pageSize?: string) {
    return this.reports.findAll(status, page ? Number(page) : undefined, pageSize ? Number(pageSize) : undefined);
  }

  @Get('open-count')
  @UseGuards(RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
  @Roles(UserRole.ADMIN)
  async openCount(@Query('targetType') targetType?: 'PROPERTY' | 'MARKETPLACE_ITEM') {
    return { count: await this.reports.countOpen(targetType) };
  }

  /// Full detail for one report — reached by tapping a row (Reports tab or
  /// the dashboard's activity feed). Registered after the static routes
  /// above ('mine', 'open-count') so this `:id` wildcard doesn't shadow them.
  @Get(':id')
  @UseGuards(RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
  @Roles(UserRole.ADMIN)
  findOne(@Param('id') id: string) {
    return this.reports.findOne(id);
  }

  @Patch(':id/status')
  @UseGuards(RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
  @Roles(UserRole.ADMIN)
  setStatus(@Param('id') id: string, @Body() dto: SetReportStatusDto) {
    return this.reports.setStatus(id, dto.status);
  }

  @Patch(':id/transfer')
  @UseGuards(RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
  @Roles(UserRole.ADMIN)
  transfer(@Param('id') id: string, @Body() dto: TransferReportDto) {
    return this.reports.transfer(id, dto.adminId);
  }
}
