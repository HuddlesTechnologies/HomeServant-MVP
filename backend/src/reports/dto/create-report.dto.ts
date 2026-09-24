import { IsEnum, IsOptional, IsString, IsUUID, MinLength } from 'class-validator';
import { ReportTargetType } from '@prisma/client';

export class CreateReportDto {
  @IsEnum(ReportTargetType)
  targetType!: ReportTargetType;

  @IsOptional()
  @IsUUID()
  propertyId?: string;

  @IsOptional()
  @IsUUID()
  productId?: string;

  @IsString()
  @MinLength(10, { message: 'Give a bit more detail (at least 10 characters)' })
  reason!: string;
}
