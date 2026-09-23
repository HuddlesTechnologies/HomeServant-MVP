import { ArrayMaxSize, IsArray, IsEnum, IsInt, IsOptional, IsString, IsUrl, Min, MinLength } from 'class-validator';
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

  /// Together with [imageUrl] (the cover), the Flutter client caps a
  /// listing at 6 photos total and requires at least 2 — this mirrors the
  /// upper bound server-side so that limit can't be bypassed by calling
  /// the API directly.
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(5)
  @IsUrl({}, { each: true })
  galleryUrls?: string[];
}
