import { Injectable, Logger } from '@nestjs/common';
import { OtpProvider } from './otp-provider.interface';

/// Development-only stand-in: logs the code instead of sending it. This
/// is what OTP_PROVIDER=console (the .env.example default) wires up —
/// never point this at production, since anyone with server log access
/// could read every code.
@Injectable()
export class ConsoleOtpProvider implements OtpProvider {
  private readonly logger = new Logger('OTP');

  async send(destination: string, code: string): Promise<void> {
    this.logger.warn(`[DEV ONLY] OTP for ${destination}: ${code}`);
  }
}
