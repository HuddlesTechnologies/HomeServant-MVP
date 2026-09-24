import { IsEmail, IsEnum, IsOptional, IsString, MinLength } from 'class-validator';
import { AdminLevel } from '@prisma/client';

export class CreateAdminDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8, { message: 'Password must be at least 8 characters' })
  password!: string;

  @IsString()
  fullName!: string;

  /// Ignored by the bootstrap endpoint (always SUPER_ADMIN there — see
  /// AdminService.bootstrapFirstAdmin); required when a SUPER_ADMIN
  /// creates an additional admin from the console.
  @IsOptional()
  @IsEnum(AdminLevel)
  level?: AdminLevel;
}
