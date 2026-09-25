import { IsDateString, IsInt, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateBookingDto {
  @IsUUID()
  propertyId!: string;

  /// Required for a Shortlet property (the requested check-in date,
  /// validated in BookingsService.create) — optional for everything else,
  /// since a non-Shortlet rental now charges immediately on creation and
  /// the tenant proposes an inspection date later, whenever ready (see
  /// BookingsService.proposeInspection), not at booking-request time.
  @IsOptional()
  @IsDateString()
  requestedDate?: string;

  /// Required (and only meaningful) for a Shortlet property — ignored for
  /// every other category.
  @IsOptional()
  @IsInt()
  @Min(1)
  nights?: number;

  @IsOptional()
  @IsString()
  message?: string;
}
