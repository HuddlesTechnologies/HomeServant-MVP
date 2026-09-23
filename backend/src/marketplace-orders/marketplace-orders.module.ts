import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { VendorsModule } from '../vendors/vendors.module';
import { MarketplaceOrdersController } from './marketplace-orders.controller';
import { MarketplaceOrdersService } from './marketplace-orders.service';

@Module({
  imports: [AuthModule, VendorsModule],
  controllers: [MarketplaceOrdersController],
  providers: [MarketplaceOrdersService],
})
export class MarketplaceOrdersModule {}
