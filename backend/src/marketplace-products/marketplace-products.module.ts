import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { VendorsModule } from '../vendors/vendors.module';
import { MarketplaceProductsController } from './marketplace-products.controller';
import { MarketplaceProductsService } from './marketplace-products.service';

@Module({
  imports: [AuthModule, VendorsModule],
  controllers: [MarketplaceProductsController],
  providers: [MarketplaceProductsService],
  exports: [MarketplaceProductsService],
})
export class MarketplaceProductsModule {}
