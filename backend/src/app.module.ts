import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from './auth/auth.module';
import { BookingsModule } from './bookings/bookings.module';
import { ChatModule } from './chat/chat.module';
import { FavoritesModule } from './favorites/favorites.module';
import { HealthController } from './health/health.controller';
import { MarketplaceOrdersModule } from './marketplace-orders/marketplace-orders.module';
import { MarketplaceProductsModule } from './marketplace-products/marketplace-products.module';
import { NotificationsModule } from './notifications/notifications.module';
import { PaystackModule } from './paystack/paystack.module';
import { PrismaModule } from './prisma/prisma.module';
import { PropertiesModule } from './properties/properties.module';
import { ReviewsModule } from './reviews/reviews.module';
import { StorageModule } from './storage/storage.module';
import { UsersModule } from './users/users.module';
import { VendorsModule } from './vendors/vendors.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    AuthModule,
    UsersModule,
    PropertiesModule,
    BookingsModule,
    FavoritesModule,
    StorageModule,
    ReviewsModule,
    ChatModule,
    VendorsModule,
    MarketplaceProductsModule,
    MarketplaceOrdersModule,
    PaystackModule,
    NotificationsModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
