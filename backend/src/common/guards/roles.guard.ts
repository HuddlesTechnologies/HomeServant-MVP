import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@prisma/client';
import { Request } from 'express';
import { PrismaService } from '../../prisma/prisma.service';
import { ROLES_KEY } from '../decorators/roles.decorator';
import { AuthenticatedUser } from '../../auth/strategies/jwt.strategy';

/// Pairs with @Roles(...) and must run after JwtAuthGuard (so
/// request.user is already populated) — `@UseGuards(JwtAuthGuard, RolesGuard)`.
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const required = this.reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!required || required.length === 0) return true;

    const { user } = context.switchToHttp().getRequest<Request & { user: AuthenticatedUser }>();
    if (!user || !required.includes(user.role)) {
      throw new ForbiddenException('You do not have access to this resource');
    }

    // Every other role's routes trust the JWT's own claims (see
    // JwtStrategy) rather than paying a DB round-trip per request. Admin
    // routes can't afford that trust window the same way: a demoted
    // (AdminService.setAdminLevel) or removed (AdminService.removeAdmin,
    // which deletes the account outright) admin must lose access on their
    // very next request, not whenever their up-to-15-minute access token
    // happens to expire. So for ADMIN-gated routes only, re-check against
    // the database and refresh `user.adminLevel` in place from it —
    // AdminLevelGuard runs right after this and reads that same
    // request.user, so a level change takes effect immediately too.
    if (required.includes(UserRole.ADMIN)) {
      const current = await this.prisma.user.findUnique({
        where: { id: user.sub },
        select: { role: true, adminLevel: true },
      });
      if (!current || !required.includes(current.role)) {
        throw new ForbiddenException('You do not have access to this resource');
      }
      user.adminLevel = current.adminLevel ?? undefined;
    }

    return true;
  }
}
