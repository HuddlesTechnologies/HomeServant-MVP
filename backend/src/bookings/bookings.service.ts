import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BookingStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateBookingDto } from './dto/create-booking.dto';

@Injectable()
export class BookingsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(tenantId: string, dto: CreateBookingDto) {
    const property = await this.prisma.property.findUnique({ where: { id: dto.propertyId } });
    if (!property) throw new NotFoundException('Property not found');

    return this.prisma.booking.create({
      data: {
        propertyId: dto.propertyId,
        tenantId,
        requestedDate: dto.requestedDate ? new Date(dto.requestedDate) : undefined,
        message: dto.message,
      },
      include: { property: true },
    });
  }

  findForTenant(tenantId: string) {
    return this.prisma.booking.findMany({
      where: { tenantId },
      include: { property: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  /// Every pending/resolved booking across every property this landlord
  /// owns — the data behind the Bookings tab's "Upcoming Bookings" card
  /// and its "See all" history view.
  findForLandlord(landlordId: string) {
    return this.prisma.booking.findMany({
      where: { property: { landlordId } },
      include: { property: true, tenant: { select: { id: true, fullName: true, email: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async respond(id: string, landlordId: string, accepted: boolean) {
    const booking = await this.prisma.booking.findUnique({ where: { id }, include: { property: true } });
    if (!booking) throw new NotFoundException('Booking not found');
    if (booking.property.landlordId !== landlordId) {
      throw new ForbiddenException('You do not own the property this booking is for');
    }

    return this.prisma.booking.update({
      where: { id },
      data: { status: accepted ? BookingStatus.ACCEPTED : BookingStatus.DECLINED },
    });
  }
}
