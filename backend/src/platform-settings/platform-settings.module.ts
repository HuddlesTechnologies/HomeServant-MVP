import { Global, Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PaymentsModule } from '../payments/payments.module';
import { PlatformSettingsController } from './platform-settings.controller';
import { PlatformSettingsService } from './platform-settings.service';

/// Global so listings, bookings and payments can read the switches without
/// imports. Service only — the admin endpoint lives in
/// PlatformControlsModule, since it also needs PaymentsService (which
/// itself depends on this service).
@Global()
@Module({
  imports: [NotificationsModule, MailModule],
  providers: [PlatformSettingsService],
  exports: [PlatformSettingsService],
})
export class PlatformSettingsModule {}

@Module({
  imports: [AuthModule, PaymentsModule],
  controllers: [PlatformSettingsController],
})
export class PlatformControlsModule {}
