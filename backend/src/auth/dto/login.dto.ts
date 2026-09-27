import { NormalizeEmail } from '../../common/decorators/normalize-email.decorator';

export const SIGN_IN_PORTALS = ['APP', 'ADMIN', 'TENANT', 'LANDLORD'] as const;
export type SignInPortal = (typeof SIGN_IN_PORTALS)[number];
import { IsBoolean, IsEmail, IsIn, IsOptional, IsString } from 'class-validator';

export class LoginDto {
  @NormalizeEmail()
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

  /// Client-supplied phone model (e.g. "iPhone 14 Pro") — persisted to
  /// `User.lastLoginDeviceModel` so the admin console can show it. Optional
  /// so an older client build or a web login doesn't fail validation.
  @IsOptional()
  @IsString()
  deviceModel?: string;

  /// Which sign-in page this came from, and so which accounts it takes:
  /// 'TENANT' / 'LANDLORD' only that role, 'ADMIN' (the admin console)
  /// only admins, 'APP' (older app builds) any non-admin. Checked right
  /// after the password, before any code is sent or token issued.
  /// Optional so an older client build keeps working.
  @IsOptional()
  @IsIn(SIGN_IN_PORTALS)
  portal?: SignInPortal;
}
