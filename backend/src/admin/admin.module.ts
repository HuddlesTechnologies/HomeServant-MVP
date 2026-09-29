import { Module } from '@nestjs/common';
import { ActivityLogModule } from '../activity-log/activity-log.module';
import { AuthModule } from '../auth/auth.module';
import { ChatModule } from '../chat/chat.module';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { OtpModule } from '../otp/otp.module';
import { AdminBootstrapController } from './admin-bootstrap.controller';
import { AdminTransactionsController } from './admin-transactions.controller';
import { AdminTransactionsService } from './admin-transactions.service';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  imports: [AuthModule, MailModule, NotificationsModule, OtpModule, ActivityLogModule, ChatModule],
  controllers: [AdminController, AdminBootstrapController, AdminTransactionsController],
  providers: [AdminService, AdminTransactionsService],
})
export class AdminModule {}
