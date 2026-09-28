import { NormalizeEmail } from '../../common/decorators/normalize-email.decorator';
import { IsEmail, IsEnum, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { AdminLevel } from '@prisma/client';

export class CreateAdminDto {
  @NormalizeEmail()
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters' })
  password!: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  lastName?: string;

  /// Accepted when first/last aren't sent (older clients).
  @IsOptional()
  @IsString()
  fullName?: string;

  /// Ignored by the bootstrap endpoint (always SUPER_ADMIN there — see
  /// AdminService.bootstrapFirstAdmin); required when a SUPER_ADMIN
  /// creates an additional admin from the console.
  @IsOptional()
  @IsEnum(AdminLevel)
  level?: AdminLevel;
}
