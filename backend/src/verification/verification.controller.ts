import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { AdminLevel, UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { MinAdminLevel } from '../common/decorators/min-admin-level.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MustChangePasswordGuard } from '../common/guards/must-change-password.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { ReviewVerificationDto, SignVerificationUploadDto, UpdateVerificationDto } from './dto/verification.dto';
import { VerificationService } from './verification.service';

@Controller('verification')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.TENANT, UserRole.LANDLORD)
export class VerificationController {
  constructor(private readonly verification: VerificationService) {}

  /// Upload goes to the PRIVATE bucket; the client saves the returned path.
  @Post('uploads/sign')
  sign(@CurrentUser() user: AuthenticatedUser, @Body() dto: SignVerificationUploadDto) {
    return this.verification.signUpload(user.sub, dto.fileName);
  }

  @Get('me')
  mine(@CurrentUser() user: AuthenticatedUser) {
    return this.verification.mine(user.sub);
  }

  @Patch('me')
  update(@CurrentUser() user: AuthenticatedUser, @Body() dto: UpdateVerificationDto) {
    return this.verification.update(user.sub, user.role, dto);
  }
}

/// Seeing someone's ID documents and deciding on them: MODERATOR and above.
@Controller('admin/verifications')
@UseGuards(JwtAuthGuard, RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
@Roles(UserRole.ADMIN)
@MinAdminLevel(AdminLevel.MODERATOR)
export class AdminVerificationController {
  constructor(private readonly verification: VerificationService) {}

  @Get()
  list(@Query('status') status?: string) {
    return this.verification.list(status);
  }

  @Get('pending-count')
  async pendingCount() {
    return { count: await this.verification.pendingCount() };
  }

  @Get('user/:userId')
  async detail(@Param('userId') userId: string) {
    return (await this.verification.detail(userId)) ?? { status: null };
  }

  @Post('user/:userId/review')
  review(@CurrentUser() user: AuthenticatedUser, @Param('userId') userId: string, @Body() dto: ReviewVerificationDto) {
    return this.verification.review(user.sub, userId, dto.decision, dto.note);
  }

  /// Runs the ID number past the issuing body again — for a submission
  /// whose check errored, or one made before a provider was configured.
  /// Each call costs a real lookup, hence a button rather than a retry
  /// loop. A tenant whose number comes back clean is verified by it.
  @Post('user/:userId/recheck')
  recheck(@Param('userId') userId: string) {
    return this.verification.recheck(userId);
  }
}
