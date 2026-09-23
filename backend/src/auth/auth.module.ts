import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { MailModule } from '../mail/mail.module';
import { OtpModule } from '../otp/otp.module';
import { AccountCleanupService } from './account-cleanup.service';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './strategies/jwt.strategy';

@Module({
  imports: [PassportModule, JwtModule.register({}), OtpModule, MailModule],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy, AccountCleanupService],
  exports: [JwtModule, PassportModule, AuthService],
})
export class AuthModule {}
