import { PartialType } from '@nestjs/mapped-types';
import { IsBoolean, IsOptional, IsString } from 'class-validator';
import { CreateVendorProfileDto } from './create-vendor-profile.dto';

export class UpdateVendorProfileDto extends PartialType(CreateVendorProfileDto) {
  @IsOptional()
  @IsString()
  bankName?: string;

  @IsOptional()
  @IsString()
  accountNumber?: string;

  @IsOptional()
  @IsString()
  accountName?: string;

  /// "Deactivate Shop" — false hides every one of this vendor's products
  /// from the public catalog without deleting anything.
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
