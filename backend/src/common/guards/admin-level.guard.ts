import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AdminLevel } from '@prisma/client';
import { Request } from 'express';
import { MIN_ADMIN_LEVEL_KEY } from '../decorators/min-admin-level.decorator';
import { AuthenticatedUser } from '../../auth/strategies/jwt.strategy';

/// Declaration order in the Prisma schema *is* the rank — see
/// AdminLevel's doc comment there.
const RANK: Record<AdminLevel, number> = {
  SUPPORT: 0,
  MODERATOR: 1,
  SUPER_ADMIN: 2,
};

/// Pairs with `@MinAdminLevel(...)` and must run after JwtAuthGuard +
/// RolesGuard (so `request.user` is populated and already confirmed to
/// be an ADMIN role) — `@UseGuards(JwtAuthGuard, RolesGuard,
/// AdminLevelGuard)`. A route with no `@MinAdminLevel(...)` at all is
/// open to any admin tier.
@Injectable()
export class AdminLevelGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<AdminLevel | undefined>(MIN_ADMIN_LEVEL_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required) return true;

    const { user } = context.switchToHttp().getRequest<Request & { user: AuthenticatedUser }>();
    if (!user?.adminLevel || RANK[user.adminLevel] < RANK[required]) {
      throw new ForbiddenException('Your admin level does not permit this action');
    }
    return true;
  }
}
