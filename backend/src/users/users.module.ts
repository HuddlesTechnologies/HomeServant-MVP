import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PaystackModule } from '../paystack/paystack.module';
import { StorageModule } from '../storage/storage.module';
import { UsersController } from './users.controller';
import { UsersService } from './users.service';

@Module({
  imports: [AuthModule, PaystackModule, NotificationsModule, StorageModule],
  controllers: [UsersController],
  providers: [UsersService],
  exports: [UsersService],
})
export class UsersModule {}
