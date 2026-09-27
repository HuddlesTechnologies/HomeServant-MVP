import { NormalizeEmail } from '../../common/decorators/normalize-email.decorator';
import { IsEmail, IsString, MinLength } from 'class-validator';

export class UpdateUserEmailDto {
  @NormalizeEmail()
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(10, { message: 'Give a bit more detail (at least 10 characters) — this is recorded in the admin activity log' })
  reason!: string;
}
