import { SetMetadata } from '@nestjs/common';
import { UserRole } from '@prisma/client';

export const ROLES_KEY = 'roles';

/// Marks a route as restricted to the given roles — read by RolesGuard.
/// A route with no @Roles(...) at all is open to any authenticated user.
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES_KEY, roles);
