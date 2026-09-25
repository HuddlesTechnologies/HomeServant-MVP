import { ArrayMaxSize, IsArray, IsEnum, IsInt, IsOptional, IsString, IsUrl, Max, Min, MinLength } from 'class-validator';
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

  /// Required for every non-Shortlet category at listing time (enforced
  /// in PropertiesService.create, not here, since the rule depends on
  /// [category]) — how long a lease runs once a tenant moves in.
  /// Meaningless for Shortlet, where a stay's length comes from however
  /// many nights the tenant books instead.
  @IsOptional()
  @IsInt()
  @Min(6)
  @Max(24)
  rentDurationMonths?: number;
}
