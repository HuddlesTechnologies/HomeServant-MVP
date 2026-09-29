import { Body, Controller, Get, HttpCode, HttpStatus, Param, Post, UseGuards } from '@nestjs/common';
import { IsString, MaxLength, MinLength } from 'class-validator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { AdminLevel, UserRole } from '@prisma/client';
import { MinAdminLevel } from '../common/decorators/min-admin-level.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { AdminLevelGuard } from '../common/guards/admin-level.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MustChangePasswordGuard } from '../common/guards/must-change-password.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { PaymentsService } from '../payments/payments.service';

class RefundTenantDto {
  @IsString()
  @MinLength(10, { message: 'Give a reason (at least 10 characters); the tenant and landlord see it' })
  @MaxLength(500)
  reason!: string;
}

/// Payouts and refunds needing attention (admin console) — moderators and
/// super admins. Every action goes through the same double-payment-safe
/// release/refund as the automatic ones (see
/// PaymentsService.releasePaymentToRecipient / retryRefund /
/// adminRefundBooking), and a full refund needs a written reason both
/// sides see.
@Controller('admin/payouts')
@UseGuards(JwtAuthGuard, RolesGuard, AdminLevelGuard, MustChangePasswordGuard)
@Roles(UserRole.ADMIN)
@MinAdminLevel(AdminLevel.MODERATOR)
export class AdminPayoutsController {
  constructor(private readonly payments: PaymentsService) {}

  @Get()
  list() {
    return this.payments.stuckPayouts();
  }

  /// HomeServant's Paystack balance — payouts are sent from it — and
  /// whether that's the test or live balance.
  @Get('balance')
  async balance() {
    return { balanceKobo: await this.payments.paystackBalanceKobo(), mode: this.payments.paystackMode() };
  }

  @Get('count')
  async count() {
    return { count: await this.payments.stuckPayoutCount() };
  }

  @Post(':paymentId/retry')
  @HttpCode(HttpStatus.OK)
  retry(@Param('paymentId') paymentId: string) {
    return this.payments.retryPayout(paymentId);
  }

  /// Retry a refund that failed, exactly as it was first asked for.
  @Post(':paymentId/retry-refund')
  @HttpCode(HttpStatus.OK)
  retryRefund(@CurrentUser() user: AuthenticatedUser, @Param('paymentId') paymentId: string) {
    return this.payments.retryRefund(paymentId, user.sub);
  }

  /// Refund the tenant in full (money still held, before move-in / stay).
  @Post(':paymentId/refund-tenant')
  @HttpCode(HttpStatus.OK)
  refundTenant(@CurrentUser() user: AuthenticatedUser, @Param('paymentId') paymentId: string, @Body() dto: RefundTenantDto) {
    return this.payments.adminRefundBooking(paymentId, user.sub, dto.reason);
  }
}
