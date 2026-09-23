import { IsEnum, IsOptional, IsString, IsUrl, MinLength } from 'class-validator';
import { MarketplaceCategory } from '@prisma/client';

export class CreateVendorProfileDto {
  @IsString()
  @MinLength(2)
  businessName!: string;

  @IsEnum(MarketplaceCategory)
  category!: MarketplaceCategory;

  @IsString()
  state!: string;

  @IsOptional()
  @IsString()
  rcNumber?: string;

  @IsOptional()
  @IsUrl()
  logoUrl?: string;
}
