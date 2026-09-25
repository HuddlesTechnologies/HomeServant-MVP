import { Body, Controller, Delete, HttpCode, HttpStatus, Patch, Post, Req, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import type { Request } from 'express';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { AuthService } from './auth.service';
import { AuthenticatedUser } from './strategies/jwt.strategy';
import { ChangePasswordDto } from './dto/change-password.dto';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { GoogleAuthDto } from './dto/google-auth.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { ResendOtpDto } from './dto/resend-otp.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { SignupDto } from './dto/signup.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  // Strict throttling below: these are all unauthenticated, brute-forceable
  // endpoints (credential guessing, OTP guessing, account enumeration) —
  // 5 requests/min/IP is generous for a genuine user, tight for an attacker.
  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('signup')
  signup(@Body() dto: SignupDto) {
    return this.auth.signup(dto);
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('verify-signup')
  @HttpCode(HttpStatus.OK)
  verifySignup(@Body() dto: VerifyOtpDto) {
    return this.auth.verifySignupOtp(dto);
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('login')
  @HttpCode(HttpStatus.OK)
  login(@Body() dto: LoginDto, @Req() req: Request) {
    return this.auth.login(dto, req.ip);
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('google')
  @HttpCode(HttpStatus.OK)
  googleAuth(@Body() dto: GoogleAuthDto) {
    return this.auth.googleAuth(dto);
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('verify-2fa')
  @HttpCode(HttpStatus.OK)
  verifyTwoFactor(@Body() dto: VerifyOtpDto, @Req() req: Request) {
    return this.auth.verifyLoginOtp(dto, req.ip);
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('resend-otp')
  @HttpCode(HttpStatus.OK)
  resendOtp(@Body() dto: ResendOtpDto) {
    return this.auth.resendOtp(dto);
  }

  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@Body() dto: RefreshTokenDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @Post('logout')
  @HttpCode(HttpStatus.NO_CONTENT)
  async logout(@Body() dto: RefreshTokenDto): Promise<void> {
    await this.auth.logout(dto.refreshToken);
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('forgot-password')
  @HttpCode(HttpStatus.OK)
  forgotPassword(@Body() dto: ForgotPasswordDto) {
    return this.auth.forgotPassword(dto);
  }

  @Throttle({ default: { limit: 5, ttl: 60000 } })
  @Post('reset-password')
  @HttpCode(HttpStatus.NO_CONTENT)
  async resetPassword(@Body() dto: ResetPasswordDto): Promise<void> {
    await this.auth.resetPassword(dto);
  }

  @Patch('password')
  @UseGuards(JwtAuthGuard)
  changePassword(@CurrentUser() user: AuthenticatedUser, @Body() dto: ChangePasswordDto, @Req() req: Request) {
    return this.auth.changePassword(user.sub, dto, req.ip);
  }

  @Patch('deactivate')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.NO_CONTENT)
  async deactivate(@CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.auth.deactivate(user.sub);
  }

  @Delete('me')
  @UseGuards(JwtAuthGuard)
  @HttpCode(HttpStatus.NO_CONTENT)
  async deleteAccount(@CurrentUser() user: AuthenticatedUser): Promise<void> {
    await this.auth.deleteAccount(user.sub);
  }
}
