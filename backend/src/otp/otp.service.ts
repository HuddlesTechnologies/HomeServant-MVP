import { BadRequestException, Inject, Injectable } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { OtpPurpose } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OTP_PROVIDER } from './otp.constants';
import { OtpProvider } from './otp-provider.interface';

export const CODE_TTL_MINUTES = 10;
const MAX_ATTEMPTS = 5;
/// How many of the most recent unexpired codes are accepted, so a resend
/// doesn't invalidate the earlier code: people often type the code from
/// the first email, which is frequently the one that arrived.
const ACCEPTED_RECENT_CODES = 3;

@Injectable()
export class OtpService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(OTP_PROVIDER) private readonly provider: OtpProvider,
  ) {}

  /// Generates a 4-digit code (matching the Flutter client's OTP input,
  /// which is 4 boxes), stores its hash, and sends it through whichever
  /// OtpProvider is configured.
  async issue(destination: string, purpose: OtpPurpose, userId?: string): Promise<void> {
    const code = await this.generate(destination, purpose, userId);
    await this.provider.send(destination, code);
  }

  /// Same as [issue] but hands back the plaintext code instead of sending
  /// it through [OtpProvider] — for a caller that needs to fold the code
  /// into a larger custom email (e.g. AdminService's invite email, which
  /// also carries a temporary password) rather than the bare-code
  /// template every other OTP purpose uses.
  async generate(destination: string, purpose: OtpPurpose, userId?: string): Promise<string> {
    const code = String(Math.floor(1000 + Math.random() * 9000));
    const codeHash = await bcrypt.hash(code, 10);

    await this.prisma.otpCode.create({
      data: {
        destination,
        purpose,
        codeHash,
        userId,
        expiresAt: new Date(Date.now() + CODE_TTL_MINUTES * 60_000),
      },
    });

    return code;
  }

  /// Verifies [code] against the few most recent unconsumed, unexpired
  /// codes issued for [destination]/[purpose] (any of them works, so an
  /// earlier email still counts after a resend). Using one consumes them
  /// all. Throws on any failure rather than returning a boolean, so callers
  /// can't accidentally ignore it.
  ///
  /// Wrong guesses are capped at [MAX_ATTEMPTS] across those codes (counted
  /// on the newest) — a 4-digit code has only 10,000 possibilities, so
  /// without this it could be brute-forced within its 10-minute expiry.
  /// Requesting a fresh code resets the count, since the newest code is new.
  async verify(destination: string, purpose: OtpPurpose, code: string): Promise<void> {
    const records = await this.prisma.otpCode.findMany({
      where: { destination, purpose, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
      take: ACCEPTED_RECENT_CODES,
    });

    if (records.length === 0) {
      throw new BadRequestException('This code has expired — tap Resend to get a new one.');
    }
    const newest = records[0];
    if (newest.attempts >= MAX_ATTEMPTS) {
      throw new BadRequestException('Too many incorrect attempts — tap Resend to get a new code.');
    }

    let matched = false;
    for (const record of records) {
      if (await bcrypt.compare(code, record.codeHash)) {
        matched = true;
        break;
      }
    }
    if (!matched) {
      await this.prisma.otpCode.update({ where: { id: newest.id }, data: { attempts: { increment: 1 } } });
      throw new BadRequestException('Incorrect code.');
    }

    await this.prisma.otpCode.updateMany({
      where: { destination, purpose, consumedAt: null },
      data: { consumedAt: new Date() },
    });
  }
}
