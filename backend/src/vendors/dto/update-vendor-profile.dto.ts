import { PartialType } from '@nestjs/mapped-types';
import { IsBoolean, IsOptional, IsString, Length } from 'class-validator';
import { CreateVendorProfileDto } from './create-vendor-profile.dto';

export class UpdateVendorProfileDto extends PartialType(CreateVendorProfileDto) {
  /// Bank code + account number only — mirrors UpdateBankDetailsDto's
  /// exact contract (see UsersService.updateBankDetails). There is no
  /// `accountName` field here on purpose: VendorsService.update resolves
  /// the real name server-side via PaystackService.resolveAccount and
  /// persists that, never anything the client sends directly.
  @IsOptional()
  @IsString()
  bankCode?: string;

  /// Nigerian NUBAN account numbers are always 10 digits.
  @IsOptional()
  @IsString()
  @Length(10, 10)
  accountNumber?: string;

  /// "Deactivate Shop" — false hides every one of this vendor's products
  /// from the public catalog without deleting anything.
  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
