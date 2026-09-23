import { IsEmail, IsIn } from 'class-validator';

export class ResendOtpDto {
  @IsEmail()
  email!: string;

  /// Which flow's code to resend — the two "Resend OTP" screens the
  /// client has (signup verification, login 2FA).
  @IsIn(['SIGNUP', 'LOGIN_2FA'])
  purpose!: 'SIGNUP' | 'LOGIN_2FA';
}
