import { NormalizeEmail } from '../../common/decorators/normalize-email.decorator';
import { IsEmail, IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { AdminLevel } from '@prisma/client';

export class RequestAdminDto {
  @NormalizeEmail()
  @IsEmail()
  email!: string;

  /// First and last name are asked for separately so customers can be
  /// shown only the first name (see adminPublicName). [fullName] is still
  /// accepted from older console builds and split when the parts are missing.
  @IsOptional()
  @IsString()
  @MaxLength(60)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(60)
  lastName?: string;

  @IsOptional()
  @IsString()
  fullName?: string;

  @IsEnum(AdminLevel)
  level!: AdminLevel;
}
