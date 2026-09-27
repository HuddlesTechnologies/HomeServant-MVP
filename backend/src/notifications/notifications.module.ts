import { Module, forwardRef } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ChatModule } from '../chat/chat.module';
import { PushModule } from '../push/push.module';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';

/// forwardRef(() => ChatModule) because ChatModule itself imports this
/// module (for NotificationsService) — see ChatModule's doc comment.
@Module({
  imports: [AuthModule, forwardRef(() => ChatModule), PushModule],
  controllers: [NotificationsController],
  providers: [NotificationsService],
  exports: [NotificationsService],
})
export class NotificationsModule {}
