import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, IsString, Min } from 'class-validator';
import { MarketplaceCategory } from '@prisma/client';

export class QueryProductsDto {
  @IsOptional()
  @IsEnum(MarketplaceCategory)
  category?: MarketplaceCategory;

  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsString()
  vendorId?: string;

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
