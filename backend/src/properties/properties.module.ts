import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { ReviewsModule } from '../reviews/reviews.module';
import { StorageModule } from '../storage/storage.module';
import { PropertiesController } from './properties.controller';
import { PropertiesService } from './properties.service';

@Module({
  imports: [AuthModule, ReviewsModule, StorageModule],
  controllers: [PropertiesController],
  providers: [PropertiesService],
  exports: [PropertiesService],
})
export class PropertiesModule {}
