import { IsInt, IsOptional, IsString, Max, Min, MinLength } from 'class-validator';

export class SetPropertyBoostDto {
  /// 0 = normal, 1 = boosted, 2 = top.
  @IsInt()
  @Min(0)
  @Max(2)
  level!: number;

  /// How long the boost lasts; omit for "until changed".
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(365)
  days?: number | null;

  @IsString()
  @MinLength(5, { message: 'Say briefly why (at least 5 characters) — this is recorded in the activity log' })
  reason!: string;
}
