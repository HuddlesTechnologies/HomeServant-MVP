import { NormalizeEmail } from '../../common/decorators/normalize-email.decorator';
import { IsEmail, IsEnum, IsString } from 'class-validator';
import { AdminLevel } from '@prisma/client';

export class RequestAdminDto {
  @NormalizeEmail()
  @IsEmail()
  email!: string;

  @IsString()
  fullName!: string;

  @IsEnum(AdminLevel)
  level!: AdminLevel;
}
