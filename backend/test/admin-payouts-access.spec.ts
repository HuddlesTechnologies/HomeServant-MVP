import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AdminLevel } from '@prisma/client';
import { AdminLevelGuard } from '../src/common/guards/admin-level.guard';
import { AdminPayoutsController } from '../src/platform-settings/admin-payouts.controller';

/// Moderators can see and retry failed payouts and refunds; refunding a
/// tenant in full stays super-admin-only.
describe('Payouts & Refunds access by admin level', () => {
  const guard = new AdminLevelGuard(new Reflector());

  function allowed(handler: keyof AdminPayoutsController, adminLevel: AdminLevel): boolean {
    const context = {
      getHandler: () => AdminPayoutsController.prototype[handler],
      getClass: () => AdminPayoutsController,
      switchToHttp: () => ({ getRequest: () => ({ user: { adminLevel } }) }),
    } as unknown as ExecutionContext;
    try {
      return guard.canActivate(context);
    } catch (e) {
      if (e instanceof ForbiddenException) return false;
      throw e;
    }
  }

  it.each(['list', 'count', 'retry', 'retryRefund'] as const)('%s: moderators and super admins, not support', (handler) => {
    expect(allowed(handler, 'SUPPORT')).toBe(false);
    expect(allowed(handler, 'MODERATOR')).toBe(true);
    expect(allowed(handler, 'SUPER_ADMIN')).toBe(true);
  });

  it('refundTenant: super admins only', () => {
    expect(allowed('refundTenant', 'SUPPORT')).toBe(false);
    expect(allowed('refundTenant', 'MODERATOR')).toBe(false);
    expect(allowed('refundTenant', 'SUPER_ADMIN')).toBe(true);
  });
});
