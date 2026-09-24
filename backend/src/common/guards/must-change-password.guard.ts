import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Request } from 'express';
import { ALLOW_MUST_CHANGE_PASSWORD_KEY } from '../decorators/allow-must-change-password.decorator';
import { AuthenticatedUser } from '../../auth/strategies/jwt.strategy';

/// Blocks every admin console route for an account still signed in with
/// a one-time temporary password (see AdminService.confirmAdminOtp/
/// confirmAdminPasswordReset) until AuthService.changePassword clears
/// the flag — the Flutter console's own blocking dialog is a UX nicety,
/// not the actual boundary; this is. Must run after JwtAuthGuard (so
/// `request.user` is populated) — pairs with `@UseGuards(JwtAuthGuard,
/// RolesGuard, AdminLevelGuard, MustChangePasswordGuard)` on
/// AdminController.
@Injectable()
export class MustChangePasswordGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const allowed = this.reflector.getAllAndOverride<boolean | undefined>(ALLOW_MUST_CHANGE_PASSWORD_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (allowed) return true;

    const { user } = context.switchToHttp().getRequest<Request & { user: AuthenticatedUser }>();
    if (user?.mustChangePassword) {
      throw new ForbiddenException('Set your own password before using the admin console');
    }
    return true;
  }
}
