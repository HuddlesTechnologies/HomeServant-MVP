import { BadRequestException } from '@nestjs/common';
import { BookingStatus, PrismaClient } from '@prisma/client';

/// A rental booking in one of these states has a tenant's money held for
/// the property (paid, not yet moved in), so no one else can pay for it.
/// The listing itself stays visible until the tenant moves in.
export const RESERVING_STATUSES: BookingStatus[] = [
  BookingStatus.PAID_AWAITING_INSPECTION,
  BookingStatus.INSPECTION_PROPOSED,
  BookingStatus.INSPECTION_CONFIRMED,
];

/// A rental that's occupied, or already paid for by another tenant who
/// hasn't moved in yet, can't be paid for again — otherwise two tenants
/// could each pay for the same home. (Browsing hides only occupied
/// listings, so a paid-for one is still seen and can be requested.)
export async function assertRentalAvailable(
  prisma: Pick<PrismaClient, 'property' | 'booking'>,
  propertyId: string,
  tenantId: string,
): Promise<void> {
  const [property, reservedByOther] = await Promise.all([
    prisma.property.findUnique({ where: { id: propertyId }, select: { isOccupied: true } }),
    prisma.booking.count({ where: { propertyId, tenantId: { not: tenantId }, status: { in: RESERVING_STATUSES } } }),
  ]);
  if (property?.isOccupied) {
    throw new BadRequestException('This property has already been rented by another tenant');
  }
  if (reservedByOther > 0) {
    throw new BadRequestException(
      'Another tenant has already paid for this property and is due to move in. It opens up again if their booking falls through.',
    );
  }
}
