import { Module, forwardRef } from '@nestjs/common';
import { ActivityLogModule } from '../activity-log/activity-log.module';
import { AuthModule } from '../auth/auth.module';
import { MailModule } from '../mail/mail.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { StorageModule } from '../storage/storage.module';
import { ChatController } from './chat.controller';
import { ChatGateway } from './chat.gateway';
import { ChatService } from './chat.service';
import { SupportChatCleanupService } from './support-chat-cleanup.service';

/// NotificationsModule needs ChatGateway (to emit `notification:new` over
/// the same socket this module already runs) while this module needs
/// NotificationsService (ChatService creates a notification on a new
/// message) — a circular module reference, hence forwardRef on both sides,
/// same as PaymentsModule/PaystackModule.
@Module({
  imports: [AuthModule, forwardRef(() => NotificationsModule), MailModule, ActivityLogModule, StorageModule],
  controllers: [ChatController],
  providers: [ChatService, ChatGateway, SupportChatCleanupService],
  // ChatService is exported for AdminModule, whose super-admin-only Chat
  // Log endpoint (AdminService.findChatLog) delegates straight into
  // ChatService.findChatLog rather than duplicating its Prisma query.
  exports: [ChatGateway, ChatService],
})
export class ChatModule {}
