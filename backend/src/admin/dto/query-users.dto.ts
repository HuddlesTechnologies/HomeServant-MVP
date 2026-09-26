import { Transform, Type } from 'class-transformer';
import { IsBoolean, IsEnum, IsInt, IsOptional, IsString, Min } from 'class-validator';
import { UserRole } from '@prisma/client';

export class QueryUsersDto {
  @IsOptional()
  @IsEnum(UserRole)
  role?: UserRole;

  /// Matched against email and fullName, case-insensitive.
  @IsOptional()
  @IsString()
  search?: string;

  /// True to show only deactivated accounts — drives the dashboard's
  /// "Deactivated Accounts" tile and the Users tab's "Deactivated" filter.
  @IsOptional()
  @Transform(({ value }) => value === 'true' || value === true)
  @IsBoolean()
  deactivatedOnly?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  pageSize?: number = 20;
}
