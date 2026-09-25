import { Body, Controller, Headers, NotFoundException, Post } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Throttle } from '@nestjs/throttler';
import { AdminService } from './admin.service';
import { CreateAdminDto } from './dto/create-admin.dto';

/// Split out from AdminController specifically so this one route can stay
/// completely unguarded (no JwtAuthGuard/RolesGuard) without those class-
/// level guards on the rest of the admin routes accidentally applying
/// here too — NestJS guards are cumulative, not overridable per-method.
@Controller('admin')
export class AdminBootstrapController {
  constructor(
    private readonly admin: AdminService,
    private readonly config: ConfigService,
  ) {}

  /// Creates the very first admin account (always SUPER_ADMIN — see
  /// AdminService.bootstrapFirstAdmin), gated by a long random secret set
  /// as the ADMIN_BOOTSTRAP_SECRET env var (never committed, shared out
  /// of band with whoever is standing the platform up). Refuses once any
  /// admin already exists; every admin after the first is created from
  /// inside the console instead (POST /admin/admins, SUPER_ADMIN only).
  // Strict throttling: this is the single highest-value brute-force target
  // in the app — completely unauthenticated by design, gated only by a
  // shared secret header. 5/min/IP makes secret-guessing impractical
  // without affecting the one-time legitimate call.
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('bootstrap')
  bootstrap(@Headers('x-admin-bootstrap-secret') secret: string | undefined, @Body() dto: CreateAdminDto) {
    if (!secret || secret !== this.config.getOrThrow<string>('ADMIN_BOOTSTRAP_SECRET')) {
      // Same response whether the secret is missing or wrong — no
      // "close, but no" hint.
      throw new NotFoundException();
    }
    return this.admin.bootstrapFirstAdmin(dto);
  }
}
