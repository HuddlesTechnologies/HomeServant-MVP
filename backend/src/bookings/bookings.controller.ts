import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { AuthenticatedUser } from '../auth/strategies/jwt.strategy';
import { BookingsService } from './bookings.service';
import { CreateBookingDto } from './dto/create-booking.dto';
import { ProposeInspectionDto } from './dto/propose-inspection.dto';
import { RespondBookingDto } from './dto/respond-booking.dto';
import { FeedClearDto } from './dto/feed-clear.dto';
import { RenewBookingDto } from './dto/renew-booking.dto';
import { ConfirmPaymentDto } from './dto/confirm-payment.dto';

@Controller('bookings')
@UseGuards(JwtAuthGuard, RolesGuard)
export class BookingsController {
  constructor(private readonly bookings: BookingsService) {}

  @Post()
  @Roles(UserRole.TENANT)
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateBookingDto) {
    return this.bookings.create(user.sub, dto);
  }

  /// The app calls this when Paystack sends the tenant back, so the
  /// booking shows as paid right away rather than when the webhook lands.
  @Post('confirm-payment')
  @Roles(UserRole.TENANT)
  confirmPayment(@CurrentUser() user: AuthenticatedUser, @Body() dto: ConfirmPaymentDto) {
    return this.bookings.confirmPayment(dto.reference, user.sub);
  }

  @Get('mine')
  @Roles(UserRole.TENANT)
  mine(@CurrentUser() user: AuthenticatedUser) {
    return this.bookings.findForTenant(user.sub);
  }

  @Get('landlord')
  @Roles(UserRole.LANDLORD)
  forLandlord(@CurrentUser() user: AuthenticatedUser) {
    return this.bookings.findForLandlord(user.sub);
  }

  /// Clear requests from (or, with `cleared: false`, put them back on) the
  /// dashboard's Incoming Bookings feed. Doesn't decline anything.
  @Patch('landlord/feed')
  @Roles(UserRole.LANDLORD)
  setFeedCleared(@CurrentUser() user: AuthenticatedUser, @Body() dto: FeedClearDto) {
    return this.bookings.setFeedCleared(user.sub, dto.cleared, dto.bookingIds);
  }

  @Patch(':id/respond')
  @Roles(UserRole.LANDLORD)
  respond(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: RespondBookingDto) {
    return this.bookings.respond(id, user.sub, dto.accepted);
  }

  @Post(':id/pay')
  @Roles(UserRole.TENANT)
  pay(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.bookings.pay(id, user.sub);
  }

  @Post(':id/inspection')
  @Roles(UserRole.TENANT)
  proposeInspection(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: ProposeInspectionDto) {
    return this.bookings.proposeInspection(id, user.sub, dto);
  }

  /// The landlord sets (or changes) the inspection date themselves.
  @Post(':id/inspection/schedule')
  @Roles(UserRole.LANDLORD)
  scheduleInspection(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: ProposeInspectionDto) {
    return this.bookings.scheduleInspection(id, user.sub, dto);
  }

  @Patch(':id/inspection/respond')
  @Roles(UserRole.LANDLORD)
  respondToInspection(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: RespondBookingDto) {
    return this.bookings.respondToInspection(id, user.sub, dto.accepted);
  }

  @Post(':id/reject')
  @Roles(UserRole.LANDLORD)
  reject(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.bookings.rejectBooking(id, user.sub);
  }

  @Post(':id/moved-in')
  @Roles(UserRole.TENANT)
  movedIn(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.bookings.confirmMovedIn(id, user.sub);
  }

  @Post(':id/refund')
  @Roles(UserRole.TENANT)
  refund(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.bookings.refund(id, user.sub);
  }

  /// The tenancy agreement generated at move-in (see
  /// PaymentsService, `tenancyAgreement.create`). The booking's tenant or
  /// landlord only; 404 before move-in.
  @Get(':id/tenancy-agreement')
  @Roles(UserRole.TENANT, UserRole.LANDLORD)
  tenancyAgreement(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.bookings.tenancyAgreement(id, user.sub);
  }

  @Get(':id/renewal-quote')
  @Roles(UserRole.TENANT)
  renewalQuote(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.bookings.renewalQuote(id, user.sub);
  }

  /// A monthly tenant paying next month's rent — see
  /// PaymentsService.payMonthlyRent. Returns the checkout to open.
  @Post(':id/pay-month')
  @Roles(UserRole.TENANT)
  payMonth(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.bookings.payMonth(id, user.sub);
  }

  @Post(':id/renew')
  @Roles(UserRole.TENANT)
  renew(@Param('id') id: string, @CurrentUser() user: AuthenticatedUser, @Body() dto: RenewBookingDto) {
    return this.bookings.renew(id, user.sub, { amount: dto.expectedAmount, leaseMonths: dto.expectedLeaseMonths });
  }
}
