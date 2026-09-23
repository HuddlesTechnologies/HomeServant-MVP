import { ArrayMinSize, IsArray, IsEnum, IsInt, IsOptional, IsString, IsUrl, Min, MinLength } from 'class-validator';
import { FulfillmentMethod, MarketplaceCategory } from '@prisma/client';

export class CreateProductDto {
  @IsString()
  @MinLength(2)
  name!: string;

  @IsString()
  @MinLength(10)
  description!: string;

  @IsInt()
  @Min(0)
  price!: number;

  @IsInt()
  @Min(0)
  stock!: number;

  @IsEnum(MarketplaceCategory)
  category!: MarketplaceCategory;

  @IsArray()
  @ArrayMinSize(2, { message: 'At least 2 photos are required' })
  @IsUrl({}, { each: true })
  imageUrls!: string[];

  @IsOptional()
  @IsUrl()
  videoUrl?: string;

  @IsArray()
  @ArrayMinSize(1, { message: 'Pick at least one fulfillment option' })
  @IsEnum(FulfillmentMethod, { each: true })
  fulfillmentOptions!: FulfillmentMethod[];
}
