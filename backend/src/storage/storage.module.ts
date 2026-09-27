import { forwardRef, Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { StorageController } from './storage.controller';
import { StorageService } from './storage.service';

@Module({
  imports: [forwardRef(() => AuthModule)],
  controllers: [StorageController],
  providers: [StorageService],
  exports: [StorageService],
})
export class StorageModule {}
