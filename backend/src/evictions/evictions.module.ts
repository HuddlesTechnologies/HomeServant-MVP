import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { AdminEvictionsController, EvictionsController } from './evictions.controller';
import { EvictionsService } from './evictions.service';

@Module({
  imports: [AuthModule, NotificationsModule, MailModule],
  controllers: [EvictionsController, AdminEvictionsController],
  providers: [EvictionsService],
})
export class EvictionsModule {}
