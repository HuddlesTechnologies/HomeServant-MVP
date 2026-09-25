import { IsOptional, IsPhoneNumber, IsString } from 'class-validator';

/// Admin-side edit of another user's basic profile fields — deliberately
/// narrower than UsersService's own UpdateProfileDto (no email, DOB,
/// photo, 2FA, referral code — those stay self-service only). At least
/// one field must be present; enforced in AdminService.updateUser rather
/// than here since class-validator has no clean built-in for "at least
/// one of these optional fields".
export class UpdateUserDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsPhoneNumber('NG')
  phone?: string;

  @IsOptional()
  @IsString()
  houseAddress?: string;
}
