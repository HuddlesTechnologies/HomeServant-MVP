import { IsIn, IsOptional, IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class CreateEvictionDto {
  @IsUUID()
  bookingId!: string;

  @IsString()
  @MinLength(20, { message: 'Explain the reason in a bit more detail (at least 20 characters) — a super admin reviews it' })
  @MaxLength(2000)
  reason!: string;
}

export class EvictionResponseDto {
  @IsString()
  @MinLength(5, { message: 'Write a short response' })
  @MaxLength(2000)
  response!: string;
}

export class ReviewEvictionDto {
  @IsIn(['APPROVE', 'REJECT'])
  decision!: 'APPROVE' | 'REJECT';

  /// Shared with both parties. Required when rejecting (enforced in the
  /// service, so the message can say why).
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  note?: string;
}
