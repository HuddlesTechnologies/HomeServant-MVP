import { IsBoolean, IsDateString, IsOptional, IsPhoneNumber, IsString, IsUrl } from 'class-validator';

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

  @IsOptional()
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
  @IsBoolean()
  twoFactorEnabled?: boolean;

  /// The inviter's code, not this user's own — see
  /// UsersService.updateProfile for how it's resolved and linked.
  @IsOptional()
  @IsString()
  referralCode?: string;
}
