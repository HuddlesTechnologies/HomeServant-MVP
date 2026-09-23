import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Resend } from 'resend';

/// General-purpose transactional email — distinct from OtpService/
/// OtpProvider (which only ever sends a numeric code). Reuses the same
/// OTP_PROVIDER/RESEND_API_KEY/RESEND_FROM_EMAIL env vars: "console"
/// logs instead of sending (development), "resend" sends for real.
@Injectable()
export class MailService {
  private readonly logger = new Logger('Mail');
  private readonly client: Resend | null;
  private readonly fromAddress: string;

  constructor(private readonly config: ConfigService) {
    const provider = this.config.get<string>('OTP_PROVIDER', 'console');
    if (provider === 'resend') {
      this.client = new Resend(this.config.getOrThrow('RESEND_API_KEY'));
      this.fromAddress = this.config.getOrThrow('RESEND_FROM_EMAIL');
    } else {
      this.client = null;
      this.fromAddress = '';
    }
  }

  async send(to: string, subject: string, html: string, text: string): Promise<void> {
    if (!this.client) {
      this.logger.log(`[console] Email to ${to}: ${subject}\n${text}`);
      return;
    }
    const { error } = await this.client.emails.send({ from: this.fromAddress, to, subject, html, text });
    if (error) {
      // Best-effort — a failed notification email shouldn't fail the
      // account action (deactivate/reactivate/etc.) that triggered it.
      this.logger.error(`Failed to send "${subject}" to ${to}: ${error.message}`);
    }
  }
}
