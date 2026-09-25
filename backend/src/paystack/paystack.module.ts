import { Module, forwardRef } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PaymentsModule } from '../payments/payments.module';
import { PaystackController } from './paystack.controller';
import { PaystackService } from './paystack.service';

@Module({
  imports: [AuthModule, forwardRef(() => PaymentsModule)],
  controllers: [PaystackController],
  providers: [PaystackService],
  exports: [PaystackService],
})
export class PaystackModule {}
