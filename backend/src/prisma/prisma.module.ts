import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

/// @Global so every feature module gets PrismaService without each one
/// re-importing PrismaModule — it's infrastructure, not a feature.
@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
