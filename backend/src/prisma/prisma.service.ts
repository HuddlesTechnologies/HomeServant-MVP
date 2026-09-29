import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';

const WRITES = new Set(['create', 'createMany', 'createManyAndReturn', 'update', 'updateMany', 'updateManyAndReturn', 'upsert', 'delete', 'deleteMany']);
const BOOKING_UPDATES = new Set(['update', 'updateMany', 'updateManyAndReturn', 'upsert']);

/// Whether this write can change what tenants see when browsing: any edit
/// to a listing (price, photos, hidden, occupied...), or a booking moving
/// to a new status (paid, moved in, refunded — see PropertiesService's
/// browse filter, which hides rentals that are taken).
export function changesListings(model: string | undefined, operation: string, args: unknown): boolean {
  if (model === 'Property') return WRITES.has(operation);
  if (model === 'Booking' && BOOKING_UPDATES.has(operation)) {
    const a = args as { data?: { status?: unknown }; update?: { status?: unknown } } | undefined;
    return a?.data?.status !== undefined || a?.update?.status !== undefined;
  }
  return false;
}

/// Records behind the admin console's "needs attention" badges: eviction
/// requests, payouts/refunds (Payments), and ID verifications. Any write to
/// them can change a count — a case filed or decided, a payout failing or
/// going through.
const ADMIN_QUEUE_MODELS = new Set(['EvictionRequest', 'Payment', 'IdentityVerification']);

export function changesAdminQueues(model: string | undefined, operation: string): boolean {
  return !!model && ADMIN_QUEUE_MODELS.has(model) && WRITES.has(operation);
}

/// The app's database client, managed by Nest's DI container — every other
/// module just injects `PrismaService` like any other provider.
///
/// Connects with DATABASE_URL (Supabase's pooled connection) through the pg
/// driver adapter, which Prisma 7 requires; the CLI's own URL is in
/// prisma.config.ts.
///
/// What Nest receives is the client extended with a query hook (Prisma's
/// replacement for the old `$use` middleware): one place that sees every
/// write, so no code path that changes a listing can forget to tell
/// connected apps (ChatGateway broadcasts `listings:changed`). `$extends`
/// returns a new client rather than changing this one, so the constructor
/// returns that client, carrying this class's own methods.
@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  private listingListeners!: (() => void)[];
  private adminQueueListeners!: (() => void)[];

  constructor() {
    super({ adapter: new PrismaPg({ connectionString: process.env.DATABASE_URL }) });
    const listeners: (() => void)[] = [];
    const adminListeners: (() => void)[] = [];
    const extended = this.$extends({
      query: {
        async $allOperations({ model, operation, args, query }) {
          const result = await query(args);
          if (changesListings(model, operation, args)) for (const listener of listeners) listener();
          if (changesAdminQueues(model, operation)) for (const listener of adminListeners) listener();
          return result;
        },
      },
    });
    return Object.assign(extended, {
      listingListeners: listeners,
      adminQueueListeners: adminListeners,
      onListingsChanged: PrismaService.prototype.onListingsChanged,
      onAdminQueuesChanged: PrismaService.prototype.onAdminQueuesChanged,
      onModuleInit: PrismaService.prototype.onModuleInit,
      onModuleDestroy: PrismaService.prototype.onModuleDestroy,
    }) as unknown as PrismaService;
  }

  /// Called after any write that may change browse results.
  onListingsChanged(listener: () => void): void {
    this.listingListeners.push(listener);
  }

  /// Called after any write that may change an admin badge count.
  onAdminQueuesChanged(listener: () => void): void {
    this.adminQueueListeners.push(listener);
  }

  async onModuleInit() {
    await this.$connect();
  }

  async onModuleDestroy() {
    await this.$disconnect();
  }
}
