import { Injectable, Logger } from '@nestjs/common';
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

  async send(destination: string, code: string): Promise<void> {
    const { error } = await this.client.emails.send({
      from: this.fromAddress,
      to: destination,
      subject: `${code} is your HomeServant verification code`,
      text: `Your HomeServant verification code is ${code}. It expires in 10 minutes.\n\nIf you didn't request this, you can ignore this email.`,
      html: `<p>Your HomeServant verification code is:</p><p style="font-size:28px;font-weight:700;letter-spacing:4px;">${code}</p><p>It expires in 10 minutes.</p><p>If you didn't request this, you can ignore this email.</p>`,
    });

    if (error) {
      this.logger.error(`Resend failed to send OTP to ${destination}: ${error.message}`);
      throw new Error('Failed to send verification code');
    }
  }
}
