import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ConsoleOtpProvider } from './console-otp.provider';
import { OTP_PROVIDER } from './otp.constants';
import { OtpService } from './otp.service';
import { ResendOtpProvider } from './resend-otp.provider';

/// The OTP_PROVIDER env var picks the delivery channel. "console"
/// (development) logs the code instead of sending it; "resend" sends a
/// real email via Resend (needs RESEND_API_KEY and RESEND_FROM_EMAIL —
/// see otp-provider.interface.ts and resend-otp.provider.ts). Add a case
/// here (e.g. "termii" for SMS) as more providers are wired up.
@Module({
  providers: [
    OtpService,
    {
      provide: OTP_PROVIDER,
      useFactory: (config: ConfigService) => {
        const provider = config.get<string>('OTP_PROVIDER', 'console');
        switch (provider) {
          case 'resend':
            return new ResendOtpProvider(config.getOrThrow('RESEND_API_KEY'), config.getOrThrow('RESEND_FROM_EMAIL'));
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
