import { SetMetadata } from '@nestjs/common';
import { AdminLevel } from '@prisma/client';

export const MIN_ADMIN_LEVEL_KEY = 'minAdminLevel';

/// Marks an admin route as requiring at least [level] — read by
/// AdminLevelGuard, which ranks AdminLevel by its declaration order in
/// the Prisma schema (SUPPORT < MODERATOR < SUPER_ADMIN). Pairs with
/// `@Roles(UserRole.ADMIN)` + `@UseGuards(JwtAuthGuard, RolesGuard,
/// AdminLevelGuard)` — RolesGuard already confirms the account is an
/// admin at all; this narrows further to which tier.
export const MinAdminLevel = (level: AdminLevel) => SetMetadata(MIN_ADMIN_LEVEL_KEY, level);
