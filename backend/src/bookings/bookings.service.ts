import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { BookingStatus, NotificationType } from '@prisma/client';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { CreateBookingDto } from './dto/create-booking.dto';

@Injectable()
export class BookingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
  ) {}

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

    const updated = await this.prisma.booking.update({
      where: { id },
      data: { status: accepted ? BookingStatus.ACCEPTED : BookingStatus.DECLINED },
    });
    await this.notifications.create(
      booking.tenantId,
      NotificationType.BOOKING_STATUS,
      accepted ? 'Booking accepted' : 'Booking declined',
      accepted
        ? `Your booking request for ${booking.property.title} was accepted.`
        : `Your booking request for ${booking.property.title} was declined.`,
    );
    return updated;
  }
}
