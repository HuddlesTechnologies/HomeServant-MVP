import { BadRequestException } from '@nestjs/common';
import { BookingStatus, PrismaClient } from '@prisma/client';

/// A rental booking in one of these states has a tenant's money held for
/// the property (paid, not yet moved in), so it's no longer up for grabs.
export const RESERVING_STATUSES: BookingStatus[] = [
  BookingStatus.PAID_AWAITING_INSPECTION,
  BookingStatus.INSPECTION_PROPOSED,
  BookingStatus.INSPECTION_CONFIRMED,
];

/// A rental that's occupied, or already paid for by another tenant who
/// hasn't moved in yet, can't be paid for again — otherwise two tenants
/// could each pay for the same home. (Browsing hides these listings too;
/// this covers a direct link, or a checkout started before it was taken.)
export async function assertRentalAvailable(
  prisma: Pick<PrismaClient, 'property' | 'booking'>,
  propertyId: string,
  tenantId: string,
): Promise<void> {
  const [property, reservedByOther] = await Promise.all([
    prisma.property.findUnique({ where: { id: propertyId }, select: { isOccupied: true } }),
    prisma.booking.count({ where: { propertyId, tenantId: { not: tenantId }, status: { in: RESERVING_STATUSES } } }),
  ]);
  if (property?.isOccupied || reservedByOther > 0) {
    throw new BadRequestException('This property has already been rented by another tenant');
  }
}
