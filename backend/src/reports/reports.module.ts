import { Module } from '@nestjs/common';
import { ChatModule } from '../chat/chat.module';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { ReportsController } from './reports.controller';
import { ReportsService } from './reports.service';

@Module({
  imports: [MailModule, NotificationsModule, ChatModule],
  controllers: [ReportsController],
  providers: [ReportsService],
})
export class ReportsModule {}
