import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { PaystackModule } from '../paystack/paystack.module';
import { VendorsController } from './vendors.controller';
import { VendorsService } from './vendors.service';

@Module({
  imports: [AuthModule, PaystackModule],
  controllers: [VendorsController],
  providers: [VendorsService],
  exports: [VendorsService],
})
export class VendorsModule {}
