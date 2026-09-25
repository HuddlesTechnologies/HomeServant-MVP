import { IsNumber, IsOptional, IsString, Min } from 'class-validator';

/// Vendor-supplied details for handing a DELIVERY-fulfillment item to the
/// courier. [pickupAddress] defaults to the vendor's business
/// name/state on file if omitted (VendorProfile has no dedicated address
/// field today), so a vendor can override it with a more precise pickup
/// address when calling this endpoint.
export class ShipOrderItemDto {
  @IsOptional()
  @IsString()
  pickupAddress?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  weightKg?: number;
}
