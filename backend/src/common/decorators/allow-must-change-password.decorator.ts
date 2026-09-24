import { SetMetadata } from '@nestjs/common';

export const ALLOW_MUST_CHANGE_PASSWORD_KEY = 'allowMustChangePassword';

/// Exempts a route from MustChangePasswordGuard — only `GET /admin/me`
/// carries this, since the console needs it to even determine which
/// tabs/actions to show before the "set your password" gate has been
/// satisfied.
export const AllowMustChangePassword = () => SetMetadata(ALLOW_MUST_CHANGE_PASSWORD_KEY, true);
