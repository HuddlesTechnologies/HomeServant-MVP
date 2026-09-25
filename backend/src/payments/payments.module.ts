import { Module, forwardRef } from '@nestjs/common';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PaystackModule } from '../paystack/paystack.module';
import { PaymentsService } from './payments.service';

/// The one home for escrow orchestration — imported by BookingsModule and
/// MarketplaceOrdersModule (which each just delegate to PaymentsService),
/// and by PaystackModule (whose webhook controller calls
/// PaymentsService.handleChargeSuccess). That last edge is what makes this
/// a circular module reference with PaystackModule (this module also
/// needs PaystackService), hence forwardRef on both sides — see
/// PaystackModule.
@Module({
  imports: [forwardRef(() => PaystackModule), NotificationsModule, MailModule],
  providers: [PaymentsService],
  exports: [PaymentsService],
})
export class PaymentsModule {}
