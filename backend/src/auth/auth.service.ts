import { randomUUID } from 'crypto';
import { BadRequestException, ConflictException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { ActivityLogType, OtpPurpose, User } from '@prisma/client';
import * as bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import { ActivityLogService } from '../activity-log/activity-log.service';
import { MailService } from '../mail/mail.service';
import { PrismaService } from '../prisma/prisma.service';
import { OtpService } from '../otp/otp.service';
import { ChangePasswordDto } from './dto/change-password.dto';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { GoogleAuthDto } from './dto/google-auth.dto';
import { LoginDto } from './dto/login.dto';
import { ResendOtpDto } from './dto/resend-otp.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
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
  mustChangePassword: boolean;
}

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
}

@Injectable()
export class AuthService {
  private readonly googleClient = new OAuth2Client();

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly otp: OtpService,
    private readonly mail: MailService,
    private readonly activityLog: ActivityLogService,
  ) {}

  async signup(dto: SignupDto): Promise<{ message: string; email: string }> {
    // Admin accounts are never self-service — see AdminService.createAdmin,
    // which is the only way one gets created.
    if (dto.role === 'ADMIN') {
      throw new ForbiddenException('Admin accounts cannot be self-registered');
    }
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

  async login(
    dto: LoginDto,
    ip?: string,
  ): Promise<
    | (TokenPair & { user: PublicUser; requiresTwoFactor: false; requiresReactivation: false })
    | { requiresTwoFactor: true; requiresReactivation: false; email: string }
    | { requiresReactivation: true; requiresTwoFactor: false; email: string }
  > {
    let user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (!user?.passwordHash) {
      // Same message whether the account doesn't exist or is Google-only
      // — telling an attacker "that email uses Google sign-in" would leak
      // which emails have accounts.
      throw new UnauthorizedException('Incorrect email or password');
    }
    if (!(await bcrypt.compare(dto.password, user.passwordHash))) {
      throw new UnauthorizedException('Incorrect email or password');
    }
    if (!user.emailVerifiedAt) {
      throw new ForbiddenException('Please verify your email before logging in');
    }

    if (user.deactivatedAt) {
      if (!dto.reactivate) {
        // The password is already proven correct at this point — the
        // client resubmits this same call with `reactivate: true` once
        // the person confirms, rather than this being a bare "anyone who
        // knows the email can reactivate" endpoint.
        return { requiresReactivation: true, requiresTwoFactor: false, email: user.email };
      }
      user = await this.reactivate(user.id);
    }

    if (user.twoFactorEnabled) {
      await this.otp.issue(user.email, OtpPurpose.LOGIN_2FA, user.id);
      return { requiresTwoFactor: true, requiresReactivation: false, email: user.email };
    }

    const tokens = await this.issueTokens(user);
    if (user.role === 'ADMIN') {
      await this.activityLog.log(ActivityLogType.ADMIN_LOGIN, { actorId: user.id, targetId: user.id, ip });
    }
    await this.recordLogin(user.id, ip, dto.deviceModel);
    return { ...tokens, user: this.toPublicUser(user), requiresTwoFactor: false, requiresReactivation: false };
  }

  /// Backs both "Resend OTP" screens (signup verification, login 2FA) —
  /// previously that button only reset the on-screen countdown and never
  /// actually requested a new code. Always resolves the same way whether
  /// or not [dto.email] is eligible (no account, already verified, or 2FA
  /// off), same reasoning as [forgotPassword] — a different response
  /// would let a caller enumerate accounts/settings by email.
  async resendOtp(dto: ResendOtpDto): Promise<{ message: string }> {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (user) {
      if (dto.purpose === 'SIGNUP' && !user.emailVerifiedAt) {
        await this.otp.issue(dto.email, OtpPurpose.SIGNUP);
      } else if (dto.purpose === 'LOGIN_2FA' && user.twoFactorEnabled) {
        await this.otp.issue(dto.email, OtpPurpose.LOGIN_2FA, user.id);
      }
    }
    return { message: 'If eligible, a new code was sent.' };
  }

  async verifyLoginOtp(dto: VerifyOtpDto, ip?: string): Promise<TokenPair & { user: PublicUser }> {
    await this.otp.verify(dto.email, OtpPurpose.LOGIN_2FA, dto.code);
    const user = await this.prisma.user.findUniqueOrThrow({ where: { email: dto.email } });
    const tokens = await this.issueTokens(user);
    if (user.role === 'ADMIN') {
      await this.activityLog.log(ActivityLogType.ADMIN_LOGIN, { actorId: user.id, targetId: user.id, ip });
    }
    await this.recordLogin(user.id, ip, dto.deviceModel);
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

  /// Verifies the Google ID token the client got back from its sign-in
  /// SDK, then finds-or-creates the matching user. Matches by googleId
  /// first, falling back to email — so an existing email/password account
  /// signing in with Google for the first time gets linked instead of
  /// erroring on a duplicate email.
  async googleAuth(
    dto: GoogleAuthDto,
    ip?: string,
  ): Promise<(TokenPair & { user: PublicUser; requiresReactivation: false }) | { requiresReactivation: true; email: string }> {
    let payload: { email?: string; email_verified?: boolean; sub: string; name?: string; picture?: string };
    try {
      const ticket = await this.googleClient.verifyIdToken({
        idToken: dto.idToken,
        audience: this.config.getOrThrow('GOOGLE_CLIENT_ID'),
      });
      const verified = ticket.getPayload();
      if (!verified) throw new Error('empty payload');
      payload = verified;
    } catch {
      throw new UnauthorizedException('Invalid Google sign-in token');
    }
    if (!payload.email || !payload.email_verified) {
      throw new UnauthorizedException("Google account's email isn't verified");
    }

    let user = await this.prisma.user.findFirst({
      where: { OR: [{ googleId: payload.sub }, { email: payload.email }] },
    });

    if (user) {
      if (!user.googleId) {
        user = await this.prisma.user.update({ where: { id: user.id }, data: { googleId: payload.sub } });
      }
    } else {
      if (!dto.role) {
        throw new BadRequestException('role is required for a new account');
      }
      if (dto.role === 'ADMIN') {
        throw new ForbiddenException('Admin accounts cannot be self-registered');
      }
      user = await this.prisma.user.create({
        data: {
          email: payload.email,
          googleId: payload.sub,
          role: dto.role,
          fullName: payload.name,
          profilePhotoUrl: payload.picture,
          emailVerifiedAt: new Date(),
        },
      });
    }

    if (user.deactivatedAt) {
      // The verified Google ID token already proves identity here (same
      // role the password plays in [login]) — the client resubmits this
      // call with `reactivate: true` and the same idToken once confirmed.
      if (!dto.reactivate) {
        return { requiresReactivation: true, email: user.email };
      }
      user = await this.reactivate(user.id);
    }

    const tokens = await this.issueTokens(user);
    await this.recordLogin(user.id, ip, dto.deviceModel);
    return { ...tokens, user: this.toPublicUser(user), requiresReactivation: false };
  }

  /// Always resolves the same way whether or not [dto.email] has an
  /// account — a different response for "no such account" vs "code sent"
  /// would let an attacker enumerate registered emails. A Google-only
  /// account (no passwordHash) also gets the generic response but no code,
  /// since there's no password on it to reset.
  /// Self-service — deliberately excludes ADMIN accounts (same "no
  /// account either way" response, so this can't be used to fingerprint
  /// which emails are admins). A locked-out admin has to go through
  /// another SUPER_ADMIN/MODERATOR instead — see
  /// AdminService.requestAdminPasswordReset.
  async forgotPassword(dto: ForgotPasswordDto): Promise<{ message: string }> {
    const user = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (user?.passwordHash && user.role !== 'ADMIN') {
      await this.otp.issue(dto.email, OtpPurpose.PASSWORD_RESET, user.id);
    }
    return { message: 'If an account exists for that email, a reset code has been sent.' };
  }

  async resetPassword(dto: ResetPasswordDto): Promise<void> {
    await this.otp.verify(dto.email, OtpPurpose.PASSWORD_RESET, dto.code);
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing?.role === 'ADMIN') {
      // Can only get here if somehow an OTP was issued anyway — refuse to
      // apply it rather than trusting [forgotPassword] was never bypassed.
      throw new ForbiddenException('Admin accounts can only be reset by another admin from the console');
    }
    const passwordHash = await bcrypt.hash(dto.newPassword, 10);
    const user = await this.prisma.user.update({ where: { email: dto.email }, data: { passwordHash } });
    // Same as changePassword — a password reset should sign out every
    // other session, not just leave old refresh tokens usable.
    await this.prisma.refreshToken.updateMany({
      where: { userId: user.id, revokedAt: null },
      data: { revokedAt: new Date() },
    });
  }

  /// Returns a fresh token pair for *this* session — necessary because an
  /// admin's access token carries `mustChangePassword`
  /// (MustChangePasswordGuard) baked in at login; without reissuing here,
  /// the console would stay locked out under that guard for the rest of
  /// the old (up to 15-minute) access token's life even after actually
  /// fixing it.
  async changePassword(userId: string, dto: ChangePasswordDto, ip?: string): Promise<TokenPair> {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (!user.passwordHash) {
      throw new BadRequestException('This account signed up with Google and has no password to change');
    }
    if (!(await bcrypt.compare(dto.currentPassword, user.passwordHash))) {
      throw new UnauthorizedException('Current password is incorrect');
    }
    const passwordHash = await bcrypt.hash(dto.newPassword, 10);
    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash, mustChangePassword: false },
    });
    // Every other session's refresh token stops working — matches the
    // usual expectation that changing your password signs out devices
    // that aren't the one that just changed it.
    await this.prisma.refreshToken.updateMany({
      where: { userId, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (updated.role === 'ADMIN') {
      await this.activityLog.log(ActivityLogType.ADMIN_PASSWORD_CHANGED, { actorId: userId, targetId: userId, ip });
    }
    return this.issueTokens(updated);
  }

  /// Settings > Danger Zone > "Deactivate Account". Hides this account's
  /// listings (see PropertiesService.findMany's landlord filter) and
  /// signs out every session. A deactivated account left untouched for 30
  /// days is permanently deleted (see AccountCleanupService); logging
  /// back in and confirming the reactivation prompt (see [login]) is the
  /// only way to undo this before then.
  /// [adminReason] is only ever passed by AdminService.deactivateUser — its
  /// presence, not just its content, is what switches the email's wording
  /// from "as requested" (this account's own owner did it) to "by an
  /// admin" (they didn't), since it'd otherwise misleadingly claim self-
  /// service on every admin-triggered suspension.
  async deactivate(userId: string, adminReason?: string): Promise<void> {
    const user = await this.prisma.user.update({ where: { id: userId }, data: { deactivatedAt: new Date() } });
    await this.prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
    const byAdmin = adminReason !== undefined;
    const reasonLine = byAdmin && adminReason ? ` Reason: ${adminReason}` : '';
    await this.mail.send(
      user.email,
      'Your HomeServant account has been deactivated',
      `<p>Hi${user.fullName ? ` ${user.fullName}` : ''},</p>
       <p>Your HomeServant account has been deactivated${byAdmin ? ' by an admin.' : ', as requested.'}${reasonLine} Your listings (if any) are hidden and you've been signed out everywhere.</p>
       <p>You can reactivate any time within the next 30 days simply by logging back in — after that, your account and its data will be permanently deleted.</p>
       <p>${byAdmin ? 'If you believe this was a mistake, contact HomeServant support.' : "If you didn't request this, please log in and reactivate your account, then change your password."}</p>`,
      `Your HomeServant account has been deactivated${byAdmin ? ' by an admin.' : ', as requested.'}${reasonLine} Your listings (if any) are hidden and you've been signed out everywhere.\n\nYou can reactivate any time within the next 30 days simply by logging back in — after that, your account and its data will be permanently deleted.\n\n${byAdmin ? 'If you believe this was a mistake, contact HomeServant support.' : "If you didn't request this, please log in and reactivate your account, then change your password."}`,
    );
  }

  /// Shared by [login] and [googleAuth] — clears the deactivation flag and
  /// emails the account holder, so a reactivation always looks the same
  /// regardless of which sign-in method triggered it.
  private async reactivate(userId: string): Promise<User> {
    const user = await this.prisma.user.update({ where: { id: userId }, data: { deactivatedAt: null } });
    await this.mail.send(
      user.email,
      'Your HomeServant account has been reactivated',
      `<p>Hi${user.fullName ? ` ${user.fullName}` : ''},</p>
       <p>Welcome back — your HomeServant account has been reactivated and your listings (if any) are visible again.</p>
       <p>If you didn't do this, please secure your account by changing your password right away.</p>`,
      `Welcome back — your HomeServant account has been reactivated and your listings (if any) are visible again.\n\nIf you didn't do this, please secure your account by changing your password right away.`,
    );
    return user;
  }

  /// Settings > Danger Zone > "Delete Account". A real, permanent delete —
  /// every relation FK'd to this user (bookings, properties, reviews,
  /// messages, vendor profile/products/orders, etc.) is modelled with
  /// `onDelete: Cascade` in the schema, so this one call is enough; there's
  /// no soft-delete flag to half-honor the "permanently removed" promise
  /// on the confirmation dialog.
  /// [adminReason] is only ever passed by AdminService.deleteUser/
  /// removeAdmin — same convention as [deactivate]. Fetched and emailed
  /// *before* the delete: there's no user row left to look up an address
  /// from afterward.
  async deleteAccount(userId: string, adminReason?: string): Promise<void> {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (user) {
      const byAdmin = adminReason !== undefined;
      const reasonLine = byAdmin && adminReason ? ` Reason: ${adminReason}` : '';
      await this.mail.send(
        user.email,
        'Your HomeServant account has been deleted',
        `<p>Hi${user.fullName ? ` ${user.fullName}` : ''},</p>
         <p>Your HomeServant account has been permanently deleted${byAdmin ? ' by an admin.' : ', as requested.'}${reasonLine} Everything tied to it — listings, bookings, orders, and messages — has been removed, and this can't be undone.</p>
         ${byAdmin ? '<p>If you believe this was a mistake, contact HomeServant support.</p>' : ''}`,
        `Your HomeServant account has been permanently deleted${byAdmin ? ' by an admin.' : ', as requested.'}${reasonLine} Everything tied to it — listings, bookings, orders, and messages — has been removed, and this can't be undone.${byAdmin ? '\n\nIf you believe this was a mistake, contact HomeServant support.' : ''}`,
      );
    }
    await this.prisma.user.delete({ where: { id: userId } });
  }

  /// Called from every actual "sign in" completion (password login,
  /// login-2FA verification, Google sign-in) — not from [issueTokens]
  /// itself, since that's also used by token refresh and password-reset
  /// completion, neither of which is a fresh "login" whose IP/device is
  /// worth recording. Previously this data (IP at least) was only ever
  /// captured for ADMIN role logins, and only into ActivityLog.
  private async recordLogin(userId: string, ip?: string, deviceModel?: string): Promise<void> {
    await this.prisma.user.update({
      where: { id: userId },
      data: { lastActiveAt: new Date(), lastLoginIp: ip, lastLoginDeviceModel: deviceModel },
    });
  }

  private async issueTokens(user: User): Promise<TokenPair> {
    const accessToken = await this.jwt.signAsync(
      {
        sub: user.id,
        email: user.email,
        role: user.role,
        adminLevel: user.adminLevel ?? undefined,
        mustChangePassword: user.mustChangePassword,
      },
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
      mustChangePassword: user.mustChangePassword,
    };
  }
}
