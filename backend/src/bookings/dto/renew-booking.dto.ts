import { IsInt, IsOptional, Min } from 'class-validator';

/// What the tenant was shown by GET /bookings/:id/renewal-quote and agreed
/// to. Both optional so older clients keep working; when sent, a renewal
/// whose price or lease length changed in the meantime is refused (409).
export class RenewBookingDto {
  @IsOptional()
  @IsInt()
  @Min(0)
  expectedAmount?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  expectedLeaseMonths?: number;
}
