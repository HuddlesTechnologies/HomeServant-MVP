import { IsBoolean, IsEnum, IsOptional, IsString } from 'class-validator';
import { UserRole } from '@prisma/client';

export class GoogleAuthDto {
  @IsString()
  idToken!: string;

  /// Required only when the Google account doesn't match an existing
  /// user — there's nothing to infer a new account's role from, so the
  /// client sends whichever role screen ("Sign in with Google" on the
  /// tenant vs landlord flow) it was tapped from.
  @IsOptional()
  @IsEnum(UserRole)
  role?: UserRole;

  /// Same meaning as LoginDto.reactivate — set on the resubmitted call
  /// after the client's confirmed reactivation prompt.
  @IsOptional()
  @IsBoolean()
  reactivate?: boolean;
}
