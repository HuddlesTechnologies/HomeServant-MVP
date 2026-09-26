import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BookingStatus, Prisma, PropertyCategory } from '@prisma/client';
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

@Injectable()
export class PropertiesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly reviews: ReviewsService,
    private readonly storage: StorageService,
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

    const page = query.page ?? 1;
    const pageSize = query.pageSize ?? 20;

    const [items, total] = await Promise.all([
      this.prisma.property.findMany({
        where,
        include: { landlord: { select: { id: true, fullName: true } } },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.property.count({ where }),
    ]);

    const ratings = await this.reviews.summaryForProperties(items.map((p) => p.id));
    const shortletAvailability = await this.shortletAvailabilityForProperties(items);
    return {
      items: items.map((p) => ({
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
      include: { landlord: { select: { id: true, fullName: true } } },
    });
    if (!property) throw new NotFoundException('Property not found');
    const ratings = await this.reviews.summaryForProperties([id]);
    const shortletAvailability = await this.shortletAvailabilityForProperties([property]);
    return { ...property, ...(ratings.get(id) ?? { avgRating: 0, reviewCount: 0 }), ...(shortletAvailability.get(id) ?? {}) };
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
    return this.prisma.property.update({ where: { id }, data: dto });
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

    const blockingBooking = await this.prisma.booking.findFirst({
      where: { propertyId: id, status: { in: ['ACCEPTED', 'PAID', 'MOVED_IN'] } },
      select: { id: true },
    });
    if (blockingBooking) {
      throw new BadRequestException(
        'This listing has an active tenancy and can’t be deleted. It can be delisted once the lease ends, or by an admin if needed sooner.',
      );
    }

    await this.prisma.property.delete({ where: { id } });
  }

  private async assertOwnership(id: string, landlordId: string): Promise<void> {
    const property = await this.prisma.property.findUnique({ where: { id }, select: { landlordId: true } });
    if (!property) throw new NotFoundException('Property not found');
    if (property.landlordId !== landlordId) {
      throw new ForbiddenException('You do not own this property');
    }
  }
}
