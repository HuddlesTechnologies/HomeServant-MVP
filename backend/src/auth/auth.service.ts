import { randomUUID } from 'crypto';
import { ConflictException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { OtpPurpose, User } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../prisma/prisma.service';
import { OtpService } from '../otp/otp.service';
import { ChangePasswordDto } from './dto/change-password.dto';
import { LoginDto } from './dto/login.dto';
import { SignupDto } from './dto/signup.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';

/// What comes back to the client after signup/login — never the password
/// hash. Mirrors the fields the Flutter app's AppState already tracks.
export interface PublicUser {
  id: string;
  email: string;
  role: User['role'];
  fullName: string | null;
  phoneNumber: string | null;
  profilePhotoUrl: string | null;
  twoFactorEnabled: boolean;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly otp: OtpService,
  ) {}

  async signup(dto: SignupDto): Promise<{ message: string; email: string }> {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) {
      throw new ConflictException('An account with this email already exists');
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);
    await this.prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        role: dto.role,
        fullName: dto.fullName,
        phoneNumber: dto.phoneNumber,
      },
    });

    await this.otp.issue(dto.email, OtpPurpose.SIGNUP);
    return { message: 'Verification code sent', email: dto.email };
  }

  async verifySignupOtp(dto: VerifyOtpDto): Promise<TokenPair & { user: PublicUser }> {
    await this.otp.verify(dto.email, OtpPurpose.SIGNUP, dto.code);
    const user = await this.prisma.user.update({
      where: { email: dto.email },
      data: { emailVerifiedAt: new Date() },
    });
    const tokens = await this.issueTokens(user);
    return { ...tokens, user: this.toPublicUser(user) };
  }

  async login(dto: LoginDto): Promise<(TokenPair & { user: PublicUser; requiresTwoFactor: false }) | { requiresTwoFactor: true; email: string }> {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (!user || !(await bcrypt.compare(dto.password, user.passwordHash))) {
      throw new UnauthorizedException('Incorrect email or password');
    }
    if (!user.emailVerifiedAt) {
      throw new ForbiddenException('Please verify your email before logging in');
    }

    if (user.twoFactorEnabled) {
      await this.otp.issue(user.email, OtpPurpose.LOGIN_2FA, user.id);
      return { requiresTwoFactor: true, email: user.email };
    }

    const tokens = await this.issueTokens(user);
    return { ...tokens, user: this.toPublicUser(user), requiresTwoFactor: false };
  }

  async verifyLoginOtp(dto: VerifyOtpDto): Promise<TokenPair & { user: PublicUser }> {
    await this.otp.verify(dto.email, OtpPurpose.LOGIN_2FA, dto.code);
    const user = await this.prisma.user.findUniqueOrThrow({ where: { email: dto.email } });
    const tokens = await this.issueTokens(user);
    return { ...tokens, user: this.toPublicUser(user) };
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    let payload: { sub: string; jti: string };
    try {
      payload = await this.jwt.verifyAsync(refreshToken, { secret: this.config.getOrThrow('JWT_REFRESH_SECRET') });
    } catch {
      throw new UnauthorizedException('Invalid or expired refresh token');
    }

    const record = await this.prisma.refreshToken.findUnique({ where: { id: payload.jti } });
    if (!record || record.revokedAt || record.expiresAt < new Date()) {
      throw new UnauthorizedException('Refresh token expired or already used');
    }
    if (!(await bcrypt.compare(refreshToken, record.tokenHash))) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    // Rotate: this token is single-use — issuing a new pair immediately
    // revokes it, so a stolen-and-replayed refresh token stops working
    // the moment the legitimate client refreshes again.
    await this.prisma.refreshToken.update({ where: { id: record.id }, data: { revokedAt: new Date() } });

    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: record.userId } });
    return this.issueTokens(user);
  }

  async logout(refreshToken: string): Promise<void> {
    try {
      const payload = await this.jwt.verifyAsync<{ jti: string }>(refreshToken, {
        secret: this.config.getOrThrow('JWT_REFRESH_SECRET'),
      });
      await this.prisma.refreshToken.updateMany({
        where: { id: payload.jti, revokedAt: null },
        data: { revokedAt: new Date() },
      });
    } catch {
      // Already invalid/expired — nothing to revoke, but logout should
      // still look successful from the client's point of view.
    }
  }

  async changePassword(userId: string, dto: ChangePasswordDto): Promise<void> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (!(await bcrypt.compare(dto.currentPassword, user.passwordHash))) {
      throw new UnauthorizedException('Current password is incorrect');
    }
    const passwordHash = await bcrypt.hash(dto.newPassword, 10);
    await this.prisma.user.update({ where: { id: userId }, data: { passwordHash } });
    // Every other session's refresh token stops working — matches the
    // usual expectation that changing your password signs out devices
    // that aren't the one that just changed it.
    await this.prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  private async issueTokens(user: User): Promise<TokenPair> {
    const accessToken = await this.jwt.signAsync(
      { sub: user.id, email: user.email, role: user.role },
      { secret: this.config.getOrThrow('JWT_ACCESS_SECRET'), expiresIn: this.config.get('JWT_ACCESS_TTL', '15m') },
    );

    const tokenId = randomUUID();
    const refreshToken = await this.jwt.signAsync(
      { sub: user.id, jti: tokenId },
      { secret: this.config.getOrThrow('JWT_REFRESH_SECRET'), expiresIn: this.config.get('JWT_REFRESH_TTL', '30d') },
    );

    const decoded = this.jwt.decode(refreshToken) as { exp: number };
    const tokenHash = await bcrypt.hash(refreshToken, 10);
    await this.prisma.refreshToken.create({
      data: { id: tokenId, tokenHash, userId: user.id, expiresAt: new Date(decoded.exp * 1000) },
    });

    return { accessToken, refreshToken };
  }

  private toPublicUser(user: User): PublicUser {
    return {
      id: user.id,
      email: user.email,
      role: user.role,
      fullName: user.fullName,
      phoneNumber: user.phoneNumber,
      profilePhotoUrl: user.profilePhotoUrl,
      twoFactorEnabled: user.twoFactorEnabled,
    };
  }
}
