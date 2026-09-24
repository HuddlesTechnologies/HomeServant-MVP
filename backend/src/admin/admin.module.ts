import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { AdminBootstrapController } from './admin-bootstrap.controller';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

@Module({
  imports: [AuthModule, MailModule, NotificationsModule],
  controllers: [AdminController, AdminBootstrapController],
  providers: [AdminService],
})
export class AdminModule {}
