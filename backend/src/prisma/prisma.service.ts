import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Prisma, PrismaClient } from '@prisma/client';

const PROPERTY_WRITES = new Set<Prisma.PrismaAction>(['create', 'createMany', 'update', 'updateMany', 'upsert', 'delete', 'deleteMany']);
const BOOKING_UPDATES = new Set<Prisma.PrismaAction>(['update', 'updateMany', 'upsert']);

/// Whether this write can change what tenants see when browsing: any edit
/// to a listing (price, photos, hidden, occupied...), or a booking moving
/// to a new status (paid, moved in, refunded — see PropertiesService's
/// browse filter, which hides rentals that are taken).
export function changesListings(params: Prisma.MiddlewareParams): boolean {
  if (params.model === 'Property') return PROPERTY_WRITES.has(params.action);
  if (params.model === 'Booking' && BOOKING_UPDATES.has(params.action)) {
    const args = params.args as { data?: { status?: unknown }; update?: { status?: unknown } } | undefined;
    return args?.data?.status !== undefined || args?.update?.status !== undefined;
  }
  return false;
}

/// Thin wrapper so Prisma's connection lifecycle is managed by Nest's DI
/// container instead of a bare module-level singleton — every other
/// module just injects `PrismaService` like any other provider.
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private readonly listingListeners: (() => void)[] = [];

  constructor() {
    super();
    // One place that sees every write, so no code path that changes a
    // listing can forget to tell connected apps (ChatGateway broadcasts).
    this.$use(async (params, next) => {
      const result = await next(params);
      if (changesListings(params)) for (const listener of this.listingListeners) listener();
      return result;
    });
  }

  /// Called after any write that may change browse results.
  onListingsChanged(listener: () => void): void {
    this.listingListeners.push(listener);
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
