import { IsEmail, IsString, Length } from 'class-validator';

/// No `purpose` field on purpose (so to speak) — which OTP purpose gets
/// checked is decided by which endpoint you call (/verify-signup vs
/// /verify-2fa), not by a client-supplied value, so a signup code can't
/// be replayed against the login-2FA check just by changing a field.
export class VerifyOtpDto {
  @IsEmail()
  email!: string;

  @IsString()
  @Length(4, 4)
  code!: string;
}
