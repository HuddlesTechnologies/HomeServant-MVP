import { BadRequestException, Inject, Injectable } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { OtpPurpose } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { OTP_PROVIDER } from './otp.constants';
import { OtpProvider } from './otp-provider.interface';

const CODE_TTL_MINUTES = 10;
const MAX_ATTEMPTS = 5;

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

    await this.provider.send(destination, code);
  }

  /// Verifies [code] against the most recent unconsumed, unexpired code
  /// issued for [destination]/[purpose]. Throws on any failure rather
  /// than returning a boolean, so callers can't accidentally ignore it.
  ///
  /// Caps wrong guesses per-code at [MAX_ATTEMPTS] — a 4-digit code has
  /// only 10,000 possibilities, so without this an attacker could just
  /// brute-force it within its 10-minute expiry window. Requesting a
  /// fresh code (`issue`) sidesteps a locked-out one automatically, since
  /// this always matches against the newest unconsumed code.
  async verify(destination: string, purpose: OtpPurpose, code: string): Promise<void> {
    const record = await this.prisma.otpCode.findFirst({
      where: { destination, purpose, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });

    if (!record) {
      throw new BadRequestException('No active code for this request — request a new one.');
    }
    if (record.attempts >= MAX_ATTEMPTS) {
      throw new BadRequestException('Too many incorrect attempts — request a new code.');
    }

    const matches = await bcrypt.compare(code, record.codeHash);
    if (!matches) {
      await this.prisma.otpCode.update({ where: { id: record.id }, data: { attempts: { increment: 1 } } });
      throw new BadRequestException('Incorrect code.');
    }

    await this.prisma.otpCode.update({ where: { id: record.id }, data: { consumedAt: new Date() } });
  }
}
