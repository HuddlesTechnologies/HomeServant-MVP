import { IsBoolean, IsEmail, IsOptional, IsString } from 'class-validator';

export class LoginDto {
  @IsEmail()
  email!: string;

  @IsString()
  password!: string;

  /// Set on the resubmitted login call after the client's confirmed
  /// "this account is deactivated — reactivate it?" prompt — see
  /// AuthService.login. Omitted/false on the first attempt, which just
  /// reports `requiresReactivation` instead of logging in.
  @IsOptional()
  @IsBoolean()
  reactivate?: boolean;
}
