import { IsString } from 'class-validator';

export class ConfirmAdminResetDto {
  @IsString()
  code!: string;
}
