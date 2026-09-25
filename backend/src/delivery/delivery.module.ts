import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ConsoleDeliveryProvider } from './console-delivery.provider';
import { DELIVERY_PROVIDER } from './delivery.constants';
import { GigLogisticsProvider } from './gig-logistics.provider';

/// The DELIVERY_PROVIDER env var picks the courier integration.
/// "console" (development, the default) just logs and returns a fake
/// shipment id; "gig" calls GIG Logistics for real (needs GIG_API_KEY
/// and GIG_API_BASE_URL — see delivery-provider.interface.ts and
/// gig-logistics.provider.ts for the big caveat: this is unverified
/// best-effort scaffolding, not a confirmed integration, since GIG has
/// no public API docs and no account/credentials exist yet). Mirrors
/// otp.module.ts's exact selection pattern.
@Module({
  providers: [
    {
      provide: DELIVERY_PROVIDER,
      useFactory: (config: ConfigService) => {
        const provider = config.get<string>('DELIVERY_PROVIDER', 'console');
        switch (provider) {
          case 'gig':
            return new GigLogisticsProvider(config.getOrThrow('GIG_API_KEY'), config.getOrThrow('GIG_API_BASE_URL'));
          case 'console':
          default:
            return new ConsoleDeliveryProvider();
        }
      },
      inject: [ConfigService],
    },
  ],
  exports: [DELIVERY_PROVIDER],
})
export class DeliveryModule {}
