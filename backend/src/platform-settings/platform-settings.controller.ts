import { Body, Controller, Get, Logger, Patch, UseGuards } from '@nestjs/common';
import { AdminLevel, UserRole } from '@prisma/client';
import { IsBoolean, IsInt, IsOptional, Max, Min } from 'class-validator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { MinAdminLevel } from '../common/decorators/min-admin-level.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MustChangePasswordGuard } from '../common/guards/must-change-password.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { PaymentsService } from '../payments/payments.service';
import { PlatformSettingsService } from './platform-settings.service';

class UpdatePlatformSettingsDto {
  @IsOptional()
  @IsBoolean()
  requireVerifiedLandlords?: boolean;

  @IsOptional()
  @IsBoolean()
  payUnverifiedLandlords?: boolean;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(20)
  maxListingImageChanges?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(180)
  listingImageLockDays?: number;

  @IsOptional()
  @IsInt()
  @Min(100)
  @Max(10_000_000)
  featuredListingFeeNaira?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(90)
  featuredListingDays?: number;

  @IsOptional()
  @IsInt()
  @Min(2)
  @Max(20)
  promotedSlotEvery?: number;
}

/// Platform Controls in the admin console — SUPER_ADMIN only.
@Controller('admin/platform-settings')
@UseGuards(JwtAuthGuard, RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
@Roles(UserRole.ADMIN)
@MinAdminLevel(AdminLevel.SUPER_ADMIN)
export class PlatformSettingsController {
  private readonly logger = new Logger('PlatformControls');

  constructor(
    private readonly settings: PlatformSettingsService,
    private readonly payments: PaymentsService,
  ) {}

  @Get()
  async get() {
    return { ...(await this.settings.get()), heldPayouts: await this.payments.heldPayoutStats() };
  }

  @Patch()
  async update(@CurrentUser() user: AuthenticatedUser, @Body() dto: UpdatePlatformSettingsDto) {
    const wasPaying = await this.settings.payUnverifiedLandlords();
    await this.settings.update(user.sub, dto);
    if (!wasPaying && dto.payUnverifiedLandlords === true) {
      // Paying unverified landlords again: send everything held so far.
      // Background, so the toggle returns straight away.
      void this.payments
        .releaseAllHeldPayouts()
        .then((n) => this.logger.log(`Released ${n} held payout(s) after "Pay unverified landlords" was switched on`))
        .catch((error) => this.logger.error(`Releasing held payouts failed: ${(error as Error).message}`));
    }
    return this.get();
  }
}
