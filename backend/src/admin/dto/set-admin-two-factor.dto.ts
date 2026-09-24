import { IsBoolean } from 'class-validator';

export class SetAdminTwoFactorDto {
  @IsBoolean()
  enabled!: boolean;
}
