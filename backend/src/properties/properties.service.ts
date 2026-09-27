import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BookingStatus, NotificationType, PaymentStatus, PriceUnit, Prisma, PropertyCategory, VerificationStatus } from '@prisma/client';
import { formatRent } from '../common/format-rent';
import { NotificationsService } from '../notifications/notifications.service';
import { PlatformSettingsService } from '../platform-settings/platform-settings.service';
import { PrismaService } from '../prisma/prisma.service';
import { ReviewsService } from '../reviews/reviews.service';
import { StorageService } from '../storage/storage.service';
import { CreatePropertyDto } from './dto/create-property.dto';
import { QueryPropertiesDto } from './dto/query-properties.dto';
import { UpdatePropertyDto } from './dto/update-property.dto';

interface ShortletAvailability {
  isCurrentlyUnavailable: boolean;
  availableAgainAt: Date | null;
  hoursUntilAvailable: number | null;
}

const HOUR_MS = 60 * 60 * 1000;

/// The landlord fields every listing response carries, including whether
/// their identity is verified (for the "Verified" badge).
const landlordInclude = {
  landlord: { select: { id: true, fullName: true, identityVerification: { select: { status: true } } } },
} as const;

type WithLandlordVerification = {
  landlord: { id: string; fullName: string | null; identityVerification: { status: VerificationStatus } | null };
};

/// Flattens the landlord's verification into the listing flags
/// (`landlordVerified`, `hiddenUntilLandlordVerified`) and drops the nested
/// record from the response.
function withLandlordVerified<T extends WithLandlordVerification>(p: T, requireVerified: boolean) {
  const { identityVerification, ...landlord } = p.landlord;
  return { ...p, landlord, ...PlatformSettingsService.listingFlags(identityVerification?.status, requireVerified) };
}

@Injectable()
export class PropertiesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly reviews: ReviewsService,
    private readonly storage: StorageService,
    private readonly platform: PlatformSettingsService,
    private readonly notifications: NotificationsService,
  ) {}

  private async verifyImages(dto: { imageUrl?: string; galleryUrls?: string[] }): Promise<void> {
    if (dto.imageUrl) await this.storage.assertIsOwnImage(dto.imageUrl);
    if (dto.galleryUrls) await this.storage.assertAreOwnImages(dto.galleryUrls);
  }

  async findMany(query: QueryPropertiesDto) {
    const where: Prisma.PropertyWhereInput = {
      state: query.state,
      category: query.category,
      landlordId: query.landlordId,
      isOccupied: query.isOccupied === undefined ? undefined : query.isOccupied === 'true',
      price: {
        gte: query.minPrice,
        lte: query.maxPrice,
      },
      // A deactivated landlord's listings are hidden rather than deleted —
      // see AuthService.deactivate and the "reactivate any time by
      // logging back in" promise on the Settings screen.
      landlord: { deactivatedAt: null },
    };
    // Platform Controls: only verified landlords' listings in general
    // browsing. A landlord fetching their own listings (landlordId) still
    // sees them all.
    const requireVerified = await this.platform.requireVerifiedLandlords();
    if (!query.landlordId && requireVerified) {
      where.landlord = { deactivatedAt: null, ...PlatformSettingsService.verifiedLandlordFilter() };
    }

    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;

    const [items, total] = await Promise.all([
      this.prisma.property.findMany({
        where,
        include: landlordInclude,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.property.count({ where }),
    ]);

    const ratings = await this.reviews.summaryForProperties(items.map((p) => p.id));
    const shortletAvailability = await this.shortletAvailabilityForProperties(items);
    return {
      items: items.map((p) => withLandlordVerified(p, requireVerified)).map((p) => ({
        ...p,
        ...(ratings.get(p.id) ?? { avgRating: 0, reviewCount: 0 }),
        ...(shortletAvailability.get(p.id) ?? {}),
      })),
      total,
      page,
      pageSize,
    };
  }

  async findOne(id: string) {
    const property = await this.prisma.property.findUnique({
      where: { id },
      include: landlordInclude,
    });
    if (!property) throw new NotFoundException('Property not found');
    const ratings = await this.reviews.summaryForProperties([id]);
    const shortletAvailability = await this.shortletAvailabilityForProperties([property]);
    return {
      ...withLandlordVerified(property, await this.platform.requireVerifiedLandlords()),
      ...(ratings.get(id) ?? { avgRating: 0, reviewCount: 0 }),
      ...(shortletAvailability.get(id) ?? {}),
    };
  }

  /// A Shortlet's "unavailable"/countdown state is derived, never stored —
  /// see Property.isOccupied's doc comment for why a Shortlet never
  /// touches that flag. Computed here (for both the list and detail
  /// views) by checking whether any PAID booking's lease range currently
  /// covers "now".
  private async shortletAvailabilityForProperties(properties: { id: string; category: PropertyCategory }[]): Promise<Map<string, ShortletAvailability>> {
    const shortletIds = properties.filter((p) => p.category === PropertyCategory.SHORTLET).map((p) => p.id);
    if (shortletIds.length === 0) return new Map();

    const now = new Date();
    const activeBookings = await this.prisma.booking.findMany({
      where: {
        propertyId: { in: shortletIds },
        status: BookingStatus.PAID,
        leaseStartDate: { lte: now },
        leaseEndDate: { gt: now },
      },
      select: { propertyId: true, leaseEndDate: true },
      orderBy: { leaseEndDate: 'asc' },
    });

    const byProperty = new Map<string, Date>();
    for (const booking of activeBookings) {
      if (!booking.leaseEndDate) continue;
      if (!byProperty.has(booking.propertyId)) byProperty.set(booking.propertyId, booking.leaseEndDate);
    }

    const result = new Map<string, ShortletAvailability>();
    for (const id of shortletIds) {
      const availableAgainAt = byProperty.get(id) ?? null;
      result.set(id, {
        isCurrentlyUnavailable: !!availableAgainAt,
        availableAgainAt,
        hoursUntilAvailable: availableAgainAt ? Math.max(0, Math.ceil((availableAgainAt.getTime() - now.getTime()) / HOUR_MS)) : null,
      });
    }
    return result;
  }

  /// Server-side payout gate: a landlord with no bank account on file
  /// can't list a property at all, since there'd be nowhere for a
  /// tenant's payment to eventually release to. This is the real
  /// enforcement — a client-side popup steering the landlord to add
  /// payout details first is separate, friendlier frontend work, not the
  /// only line of defense.
  async create(landlordId: string, dto: CreatePropertyDto) {
    await this.verifyImages(dto);
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: landlordId } });
    if (!landlord.bankCode || !landlord.accountNumber) {
      throw new BadRequestException('Please add your Payout Account details in Settings');
    }
    if (dto.category !== 'SHORTLET' && !dto.rentDurationMonths) {
      throw new BadRequestException('Set a rent duration (6–24 months) for this listing');
    }
    return this.prisma.property.create({ data: { ...dto, landlordId } });
  }

  async update(id: string, landlordId: string, dto: UpdatePropertyDto) {
    await this.assertOwnership(id, landlordId);
    await this.verifyImages(dto);
    const before = await this.prisma.property.findUniqueOrThrow({
      where: { id },
      select: { price: true, priceUnit: true, rentDurationMonths: true },
    });
    const updated = await this.prisma.property.update({ where: { id }, data: dto });
    await this.notifyTenantsOfNewTerms(updated, before);
    return updated;
  }

  /// When the rent (or its unit, or the lease length) changes, every tenant
  /// with a live booking on this listing is told what changed and what it
  /// means for them. Nothing they've already paid changes: payouts and
  /// refunds use the amount charged, and the agreement keeps the rent paid.
  /// The new terms apply to an unpaid booking if they go ahead and pay,
  /// and to a current tenant when they renew.
  private async notifyTenantsOfNewTerms(
    after: { id: string; title: string; price: number; priceUnit: PriceUnit; rentDurationMonths: number | null },
    before: { price: number; priceUnit: PriceUnit; rentDurationMonths: number | null },
  ): Promise<void> {
    const priceChanged = after.price !== before.price || after.priceUnit !== before.priceUnit;
    const leaseChanged = after.rentDurationMonths !== before.rentDurationMonths;
    if (!priceChanged && !leaseChanged) return;

    const bookings = await this.prisma.booking.findMany({
      where: {
        propertyId: after.id,
        OR: [
          { status: { in: [BookingStatus.PENDING, BookingStatus.ACCEPTED] } },
          { status: { in: [BookingStatus.PAID_AWAITING_INSPECTION, BookingStatus.INSPECTION_PROPOSED, BookingStatus.INSPECTION_CONFIRMED] } },
          { status: BookingStatus.MOVED_IN, OR: [{ leaseEndDate: null }, { leaseEndDate: { gte: new Date() } }] },
        ],
      },
      select: { tenantId: true, status: true },
      orderBy: { createdAt: 'desc' },
    });

    const changes = [
      priceChanged ? `the rent from ${formatRent(before.price, before.priceUnit)} to ${formatRent(after.price, after.priceUnit)}` : null,
      leaseChanged && before.rentDurationMonths && after.rentDurationMonths
        ? `the lease length from ${before.rentDurationMonths} to ${after.rentDurationMonths} months`
        : null,
    ].filter(Boolean);
    if (changes.length === 0) return;
    const what = `The landlord changed ${changes.join(' and ')} for ${after.title}.`;

    // One message per tenant, for their most advanced booking here.
    const rank = (status: BookingStatus) =>
      status === BookingStatus.MOVED_IN ? 2 : status === BookingStatus.PENDING || status === BookingStatus.ACCEPTED ? 0 : 1;
    const byTenant = new Map<string, BookingStatus>();
    for (const b of bookings) {
      const current = byTenant.get(b.tenantId);
      if (current === undefined || rank(b.status) > rank(current)) byTenant.set(b.tenantId, b.status);
    }

    for (const [tenantId, status] of byTenant) {
      const impact =
        rank(status) === 2
          ? "Your current lease and what you've already paid aren't affected. The new terms apply if you renew."
          : rank(status) === 1
            ? "What you've already paid isn't affected." +
              (leaseChanged && after.rentDurationMonths ? ` Your lease will run ${after.rentDurationMonths} months from move-in.` : '') +
              ' The new rent would apply if you later renew.'
            : "You haven't paid yet, so if you go ahead, you'll pay the new price.";
      await this.notifications.create(tenantId, NotificationType.BOOKING_STATUS, 'Rent changed', `${what} ${impact}`);
    }
  }

  /// Refuses to delete a listing that still has something depending on it
  /// surviving: an open/in-progress abuse Report (Report.property cascades
  /// on delete, which would destroy the very record an admin is
  /// investigating) or a Booking that's an active/paid/moved-in tenancy
  /// (same cascade problem — the only backend record of that tenancy
  /// would vanish with it). This is the landlord's own self-service
  /// delete; AdminService.removeProperty is the separate, intentional
  /// override a moderator/super admin can still use with a reason, e.g.
  /// for a listing that genuinely needs to come down regardless.
  async remove(id: string, landlordId: string): Promise<void> {
    await this.assertOwnership(id, landlordId);

    const blockingReport = await this.prisma.report.findFirst({
      where: { propertyId: id, status: { in: ['OPEN', 'IN_PROGRESS'] } },
      select: { id: true },
    });
    if (blockingReport) {
      throw new BadRequestException(
        'This listing has an open report and can’t be deleted yet. Contact support if you believe this is a mistake.',
      );
    }

    const reason = await this.deletionBlockReason(id);
    if (reason) throw new BadRequestException(reason);

    await this.prisma.property.delete({ where: { id } });
  }

  /// Why this listing can't be deleted right now, or null if it can. A
  /// delete cascades to its bookings and their payment records, so it's
  /// refused while a tenant lives there or while money is in play:
  ///
  /// - occupied: a MOVED_IN lease that hasn't ended (or has no end date),
  ///   a Shortlet stay (PAID) that is current or upcoming, or the listing
  ///   is marked occupied;
  /// - a tenant has paid and is waiting to inspect/move in (the money is
  ///   held in escrow — the landlord can reject the booking, which refunds
  ///   the tenant, and then delete);
  /// - a tenant started paying in the last two hours (the payment could
  ///   still complete after the listing is gone).
  private async deletionBlockReason(id: string): Promise<string | null> {
    const now = new Date();
    const property = await this.prisma.property.findUnique({ where: { id }, select: { isOccupied: true } });
    const occupied =
      property?.isOccupied ||
      (await this.prisma.booking.findFirst({
        where: {
          propertyId: id,
          status: { in: [BookingStatus.MOVED_IN, BookingStatus.PAID] },
          OR: [{ leaseEndDate: null }, { leaseEndDate: { gte: now } }],
        },
        select: { id: true },
      }));
    if (occupied) {
      return 'This property is occupied by a tenant and can’t be deleted. You can delete it once the lease or stay has ended.';
    }

    const escrow = await this.prisma.booking.findFirst({
      where: {
        propertyId: id,
        status: {
          in: [BookingStatus.PAID_AWAITING_INSPECTION, BookingStatus.INSPECTION_PROPOSED, BookingStatus.INSPECTION_CONFIRMED],
        },
      },
      select: { id: true },
    });
    if (escrow) {
      return 'A tenant has paid for this property and is waiting to inspect or move in. Reject their booking first (they’ll be refunded), then delete the listing.';
    }

    const paying = await this.prisma.payment.findFirst({
      where: {
        booking: { propertyId: id },
        status: PaymentStatus.INITIATED,
        createdAt: { gte: new Date(now.getTime() - 2 * 60 * 60 * 1000) },
      },
      select: { id: true },
    });
    if (paying) {
      return 'A tenant is in the middle of paying for this property. Try again in a couple of hours.';
    }
    return null;
  }

  private async assertOwnership(id: string, landlordId: string): Promise<void> {
    const property = await this.prisma.property.findUnique({ where: { id }, select: { landlordId: true } });
    if (!property) throw new NotFoundException('Property not found');
    if (property.landlordId !== landlordId) {
      throw new ForbiddenException('You do not own this property');
    }
  }
}
