import { IsEmail, IsEnum, IsString } from 'class-validator';
import { AdminLevel } from '@prisma/client';

export class RequestAdminDto {
  @IsEmail()
  email!: string;

  @IsString()
  fullName!: string;

  @IsEnum(AdminLevel)
  level!: AdminLevel;
}
