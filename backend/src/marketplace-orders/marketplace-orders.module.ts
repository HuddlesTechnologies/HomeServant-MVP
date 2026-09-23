import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { VendorsModule } from '../vendors/vendors.module';
import { MarketplaceOrdersController } from './marketplace-orders.controller';
import { MarketplaceOrdersService } from './marketplace-orders.service';

@Module({
  imports: [AuthModule, VendorsModule, NotificationsModule],
  controllers: [MarketplaceOrdersController],
  providers: [MarketplaceOrdersService],
})
export class MarketplaceOrdersModule {}
