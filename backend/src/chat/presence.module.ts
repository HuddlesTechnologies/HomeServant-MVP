import { Global, Module } from '@nestjs/common';
import { PresenceService } from './presence.service';

/// @Global (same reasoning as PrismaModule) — both ChatModule (which
/// updates it from socket connect/disconnect) and AdminModule (which reads
/// it for the admin console's user detail screen) need it, and neither
/// otherwise imports the other.
@Global()
@Module({
  providers: [PresenceService],
  exports: [PresenceService],
})
export class PresenceModule {}
