import { IsArray, IsEnum, IsInt, IsOptional, IsString, IsUrl, Min, MinLength } from 'class-validator';
import { PriceUnit, PropertyCategory } from '@prisma/client';

export class CreatePropertyDto {
  @IsString()
  @MinLength(3)
  title!: string;

  @IsString()
  @MinLength(3)
  location!: string;

  @IsString()
  state!: string;

  @IsEnum(PropertyCategory)
  category!: PropertyCategory;

  @IsInt()
  @Min(0)
  price!: number;

  @IsEnum(PriceUnit)
  priceUnit!: PriceUnit;

  @IsInt()
  @Min(0)
  bedrooms!: number;

  @IsInt()
  @Min(0)
  bathrooms!: number;

  @IsString()
  @MinLength(10)
  description!: string;

  @IsOptional()
  @IsUrl()
  imageUrl?: string;

  @IsOptional()
  @IsArray()
  @IsUrl({}, { each: true })
  galleryUrls?: string[];
}
