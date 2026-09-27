import { NormalizeEmail } from '../../common/decorators/normalize-email.decorator';
import { IsEmail } from 'class-validator';

export class ForgotPasswordDto {
  @NormalizeEmail()
  @IsEmail()
  email!: string;
}
