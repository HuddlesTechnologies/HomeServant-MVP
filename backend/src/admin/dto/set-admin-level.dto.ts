import { IsEnum } from 'class-validator';
import { AdminLevel } from '@prisma/client';

export class SetAdminLevelDto {
  @IsEnum(AdminLevel)
  level!: AdminLevel;
}
