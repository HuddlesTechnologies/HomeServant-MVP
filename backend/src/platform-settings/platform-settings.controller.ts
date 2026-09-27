import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { AdminLevel, UserRole } from '@prisma/client';
import { IsBoolean, IsOptional } from 'class-validator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { MinAdminLevel } from '../common/decorators/min-admin-level.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MustChangePasswordGuard } from '../common/guards/must-change-password.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { PlatformSettingsService } from './platform-settings.service';

class UpdatePlatformSettingsDto {
  @IsOptional()
  @IsBoolean()
  requireVerifiedLandlords?: boolean;
}

/// Platform Controls in the admin console — SUPER_ADMIN only.
@Controller('admin/platform-settings')
@UseGuards(JwtAuthGuard, RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
@Roles(UserRole.ADMIN)
@MinAdminLevel(AdminLevel.SUPER_ADMIN)
export class PlatformSettingsController {
  constructor(private readonly settings: PlatformSettingsService) {}

  @Get()
  get() {
    return this.settings.get();
  }

  @Patch()
  update(@CurrentUser() user: AuthenticatedUser, @Body() dto: UpdatePlatformSettingsDto) {
    return this.settings.update(user.sub, dto);
  }
}
