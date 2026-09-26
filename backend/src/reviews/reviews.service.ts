import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateReviewDto } from './dto/create-review.dto';

@Injectable()
export class ReviewsService {
  constructor(private readonly prisma: PrismaService) {}

  findForProperty(propertyId: string) {
    return this.prisma.review.findMany({
      where: { propertyId },
      include: { author: { select: { id: true, fullName: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  /// Every review the current user has left, across all properties — lets
  /// the tenant's History screen show their own past rating per property
  /// without a request per listing.
  findMine(authorId: string) {
    return this.prisma.review.findMany({ where: { authorId }, orderBy: { createdAt: 'desc' } });
  }

  /// One review per (property, author) — resubmitting updates the existing
  /// review rather than erroring, so a tenant can revise their rating
  /// without a separate edit endpoint. Requires the author to actually
  /// have a non-declined/non-refunded booking on this property first —
  /// same trust-boundary check ReportsService.create already makes for
  /// reporting a property, just checked here rather than left to the
  /// reviewer's own honesty (an arbitrary tenant could otherwise post a
  /// public rating on any listing they've never set foot in).
  async upsert(authorId: string, dto: CreateReviewDto) {
    const rented = await this.prisma.booking.findFirst({
      where: { tenantId: authorId, propertyId: dto.propertyId, status: { notIn: ['PENDING', 'DECLINED', 'REFUNDED'] } },
    });
    if (!rented) throw new ForbiddenException('You can only review a property you have rented');

    return this.prisma.review.upsert({
      where: { propertyId_authorId: { propertyId: dto.propertyId, authorId } },
      create: { propertyId: dto.propertyId, authorId, rating: dto.rating, comment: dto.comment },
      update: { rating: dto.rating, comment: dto.comment },
    });
  }

  async remove(id: string, authorId: string): Promise<void> {
    const review = await this.prisma.review.findUnique({ where: { id }, select: { authorId: true } });
    if (!review) throw new NotFoundException('Review not found');
    if (review.authorId !== authorId) throw new ForbiddenException('You do not own this review');
    await this.prisma.review.delete({ where: { id } });
  }

  /// Aggregate rating summary per property, batched for [findMany]'s
  /// result page rather than one query per property.
  async summaryForProperties(propertyIds: string[]): Promise<Map<string, { avgRating: number; reviewCount: number }>> {
    if (propertyIds.length === 0) return new Map();
    const grouped = await this.prisma.review.groupBy({
      by: ['propertyId'],
      where: { propertyId: { in: propertyIds } },
      _avg: { rating: true },
      _count: true,
    });
    return new Map(
      grouped.map((g) => [g.propertyId, { avgRating: g._avg.rating ?? 0, reviewCount: g._count }]),
    );
  }
}
