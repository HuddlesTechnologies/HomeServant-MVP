import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { StorageModule } from '../storage/storage.module';
import { AdminVerificationController, VerificationController } from './verification.controller';
import { VerificationService } from './verification.service';

@Module({
  imports: [AuthModule, NotificationsModule, MailModule, StorageModule],
  controllers: [VerificationController, AdminVerificationController],
  providers: [VerificationService],
})
export class VerificationModule {}
