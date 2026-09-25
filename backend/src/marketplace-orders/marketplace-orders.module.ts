import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { DeliveryModule } from '../delivery/delivery.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PaymentsModule } from '../payments/payments.module';
import { VendorsModule } from '../vendors/vendors.module';
import { MarketplaceAutoReleaseService } from './marketplace-auto-release.service';
import { MarketplaceOrdersController } from './marketplace-orders.controller';
import { MarketplaceOrdersService } from './marketplace-orders.service';

@Module({
  imports: [AuthModule, VendorsModule, NotificationsModule, DeliveryModule, PaymentsModule],
  controllers: [MarketplaceOrdersController],
  providers: [MarketplaceOrdersService, MarketplaceAutoReleaseService],
})
export class MarketplaceOrdersModule {}
