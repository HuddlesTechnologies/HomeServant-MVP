import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PaymentsModule } from '../payments/payments.module';
import { BookingsController } from './bookings.controller';
import { BookingsService } from './bookings.service';
import { LeaseLifecycleService } from './lease-lifecycle.service';

@Module({
  imports: [AuthModule, NotificationsModule, PaymentsModule, MailModule],
  controllers: [BookingsController],
  providers: [BookingsService, LeaseLifecycleService],
})
export class BookingsModule {}
