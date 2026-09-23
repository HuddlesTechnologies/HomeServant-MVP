import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

/// Requires a valid access-token JWT on the request. Applied per-route
/// with `@UseGuards(JwtAuthGuard)`, or globally in main.ts if every route
/// ends up needing auth (not done here since signup/login must stay open).
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
