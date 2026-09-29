import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/// Like JwtAuthGuard, but a request without a (valid) token still goes
/// through — `request.user` is then null. For public endpoints that show a
/// signed-in caller a little more (e.g. a landlord's own hidden listings).
@Injectable()
export class OptionalJwtAuthGuard extends AuthGuard('jwt') {
  handleRequest<TUser>(_error: unknown, user: TUser | false): TUser | null {
    return user || null;
  }
}
