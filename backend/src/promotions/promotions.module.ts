import { Module, forwardRef } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PaystackModule } from '../paystack/paystack.module';
import { PromotionsController } from './promotions.controller';
import { PromotionsService } from './promotions.service';

/// Paid "Featured" ads. Circular with PaystackModule (its webhook calls
/// PromotionsService.handleChargeSuccess, and this needs PaystackService),
/// hence forwardRef on both sides — same as PaymentsModule.
@Module({
  imports: [AuthModule, NotificationsModule, forwardRef(() => PaystackModule)],
  controllers: [PromotionsController],
  providers: [PromotionsService],
  exports: [PromotionsService],
})
export class PromotionsModule {}
