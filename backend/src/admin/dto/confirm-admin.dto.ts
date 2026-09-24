import { IsEmail, IsString } from 'class-validator';

export class ConfirmAdminDto {
  @IsEmail()
  email!: string;

  @IsString()
  code!: string;
}
