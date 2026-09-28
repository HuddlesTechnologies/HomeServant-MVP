import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ConsoleIdCheckProvider } from './console-id-check.provider';
import { ID_CHECK_PROVIDER } from './id-check.constants';
import { PremblyIdCheckProvider } from './prembly-id-check.provider';

/// The ID_CHECK_PROVIDER env var picks who ID numbers are checked with.
/// "console" (the default) checks nothing and leaves every submission for
/// a moderator — i.e. how verification behaved before this existed.
/// "prembly" looks each number up with the issuing authority through
/// Prembly/Identitypass (needs PREMBLY_X_API_KEY; PREMBLY_APP_ID only
/// matters on their legacy hosts, and PREMBLY_BASE_URL overrides the API
/// host). Mirrors otp.module.ts's selection pattern.
@Module({
  providers: [
    {
      provide: ID_CHECK_PROVIDER,
      useFactory: (config: ConfigService) => {
        const provider = config.get<string>('ID_CHECK_PROVIDER', 'console');
        switch (provider) {
          case 'prembly':
            return new PremblyIdCheckProvider(
              config.getOrThrow('PREMBLY_X_API_KEY'),
              // Only their legacy hosts need an app id; the current API
              // authenticates on the key alone, so this stays optional.
              config.get('PREMBLY_APP_ID') || null,
              config.get('PREMBLY_BASE_URL') || undefined,
            );
          case 'console':
          default:
            return new ConsoleIdCheckProvider();
        }
      },
      inject: [ConfigService],
    },
  ],
  exports: [ID_CHECK_PROVIDER],
})
export class IdCheckModule {}
