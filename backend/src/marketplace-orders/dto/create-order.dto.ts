import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsEnum, IsInt, IsString, Min, ValidateNested } from 'class-validator';
import { FulfillmentMethod, MarketplacePaymentMethod } from '@prisma/client';

export class OrderItemInputDto {
  @IsString()
  productId!: string;

  @IsInt()
  @Min(1)
  quantity!: number;

  @IsEnum(FulfillmentMethod)
  fulfillment!: FulfillmentMethod;
}

export class CreateOrderDto {
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => OrderItemInputDto)
  items!: OrderItemInputDto[];

  @IsEnum(MarketplacePaymentMethod)
  paymentMethod!: MarketplacePaymentMethod;
}
