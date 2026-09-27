import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { Resend } from 'resend';
import { OtpProvider } from './otp-provider.interface';

/// Sends the code as a transactional email via Resend. Only handles email
/// destinations — [destination] here is always an email address, since
/// this API's OTP purposes (signup, login 2FA, password reset) are all
/// email-only today.
@Injectable()
export class ResendOtpProvider implements OtpProvider {
  private readonly logger = new Logger('OTP');
  private readonly client: Resend;

  constructor(
    apiKey: string,
    private readonly fromAddress: string,
  ) {
    this.client = new Resend(apiKey);
  }

  /// Retries brief failures (Resend's per-second rate limit, a 5xx, a
  /// network blip) before giving up with a clear, retryable error. Sign-up
  /// codes, unread-message emails and admin alerts all share one Resend
  /// account, so bursts can briefly hit its rate limit.
  async send(destination: string, code: string): Promise<void> {
    const delays = [0, 800, 2000];
    let lastError = '';
    for (const delay of delays) {
      if (delay) await new Promise((resolve) => setTimeout(resolve, delay));
      try {
        const { error } = await this.attempt(destination, code);
        if (!error) return;
        lastError = `${error.name ?? ''} ${error.message}`.trim();
        // A permanent problem (bad address, unverified sender, quota used
        // up for the day) won't fix itself in two seconds — stop retrying.
        if (!/rate|limit|internal|timeout|unavailable|application_error/i.test(lastError) || /daily|quota/i.test(lastError)) break;
      } catch (err) {
        lastError = String(err);
      }
    }
    this.logger.error(`Resend failed to send OTP to ${destination}: ${lastError}`);
    throw new ServiceUnavailableException("We couldn't send your code just now. Please try again in a minute.");
  }

  private attempt(destination: string, code: string) {
    return this.client.emails.send({
      from: this.fromAddress,
      to: destination,
      subject: `${code} is your HomeServant verification code`,
      text: `Your HomeServant verification code is ${code}. It expires in 10 minutes.\n\nIf you didn't request this, you can ignore this email.`,
      html: `<p>Your HomeServant verification code is:</p><p style="font-size:28px;font-weight:700;letter-spacing:4px;">${code}</p><p>It expires in 10 minutes.</p><p>If you didn't request this, you can ignore this email.</p>`,
    });
  }
}
