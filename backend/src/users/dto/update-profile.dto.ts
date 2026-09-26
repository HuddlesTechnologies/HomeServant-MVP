import { IsBoolean, IsDateString, IsEnum, IsOptional, IsPhoneNumber, IsString, IsUrl, ValidateIf } from 'class-validator';
import { Gender, MaritalStatus } from '@prisma/client';

export class UpdateProfileDto {
  @IsOptional()
  @IsString()
  firstName?: string;

  @IsOptional()
  @IsString()
  lastName?: string;

  @IsOptional()
  @IsString()
  fullName?: string;

  /// An empty string is a deliberate "clear this field" signal (see
  /// UsersService.updateProfile, which maps it to `null`) rather than a
  /// validation failure — @IsPhoneNumber alone would reject '', so it's
  /// skipped for exactly that one value via @ValidateIf.
  @IsOptional()
  @ValidateIf((o: UpdateProfileDto) => o.phoneNumber !== '')
  @IsPhoneNumber('NG')
  phoneNumber?: string;

  @IsOptional()
  @IsString()
  houseAddress?: string;

  @IsOptional()
  @IsDateString()
  dateOfBirth?: string;

  @IsOptional()
  @IsUrl()
  profilePhotoUrl?: string;

  @IsOptional()
  @IsEnum(Gender)
  gender?: Gender;

  @IsOptional()
  @IsString()
  occupation?: string;

  @IsOptional()
  @IsEnum(MaritalStatus)
  maritalStatus?: MaritalStatus;

  @IsOptional()
  @IsBoolean()
  twoFactorEnabled?: boolean;

  /// The inviter's code, not this user's own — see
  /// UsersService.updateProfile for how it's resolved and linked.
  @IsOptional()
  @IsString()
  referralCode?: string;
}
