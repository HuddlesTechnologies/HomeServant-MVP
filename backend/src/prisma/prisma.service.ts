import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

/// Thin wrapper so Prisma's connection lifecycle is managed by Nest's DI
/// container instead of a bare module-level singleton — every other
/// module just injects `PrismaService` like any other provider.
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
