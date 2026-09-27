import { NormalizeEmail } from '../../common/decorators/normalize-email.decorator';
import { IsEmail, IsString } from 'class-validator';

export class ConfirmAdminDto {
  @NormalizeEmail()
  @IsEmail()
  email!: string;

  @IsString()
  code!: string;
}
