import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { APP_GUARD } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AdminModule } from './admin/admin.module';
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
import { ReportsModule } from './reports/reports.module';
import { ReviewsModule } from './reviews/reviews.module';
import { StorageModule } from './storage/storage.module';
import { UsersModule } from './users/users.module';
import { VendorsModule } from './vendors/vendors.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ScheduleModule.forRoot(),
    // Global rate limiting: a generous default so ordinary browsing/CRUD
    // traffic never gets blocked; per-route @Throttle overrides on
    // brute-forceable endpoints (auth, admin bootstrap) and spammable ones
    // (reports, chat) layer stricter limits on top via ThrottlerGuard's
    // named-config resolution (see those controllers).
    ThrottlerModule.forRoot([
      {
        name: 'default',
        ttl: 60000,
        limit: 100,
      },
    ]),
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
    AdminModule,
    ReportsModule,
  ],
  controllers: [HealthController],
  providers: [
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
  ],
})
export class AppModule {}
