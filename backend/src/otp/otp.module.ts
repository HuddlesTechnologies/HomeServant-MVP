import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ConsoleOtpProvider } from './console-otp.provider';
import { OTP_PROVIDER } from './otp.constants';
import { OtpService } from './otp.service';

/// The OTP_PROVIDER env var picks the delivery channel. Only "console"
/// (development) is implemented today; add a case here (e.g. "termii",
/// "resend") as real providers are wired up — see otp-provider.interface.ts.
@Module({
  providers: [
    OtpService,
    {
      provide: OTP_PROVIDER,
      useFactory: (config: ConfigService) => {
        const provider = config.get<string>('OTP_PROVIDER', 'console');
        switch (provider) {
          case 'console':
          default:
            return new ConsoleOtpProvider();
        }
      },
      inject: [ConfigService],
    },
  ],
  exports: [OtpService],
})
export class OtpModule {}
