import { NormalizeEmail } from '../../common/decorators/normalize-email.decorator';
import { IsEmail } from 'class-validator';

export class CancelAdminInviteDto {
  @NormalizeEmail()
  @IsEmail()
  email!: string;
}
