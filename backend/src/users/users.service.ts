import { Injectable, InternalServerErrorException, NotFoundException } from '@nestjs/common';
import { NotificationType } from '@prisma/client';
import { NotificationsService } from '../notifications/notifications.service';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { UpdateBankDetailsDto } from './dto/update-bank-details.dto';
import { UpdateProfileDto } from './dto/update-profile.dto';

const profileSelect = {
  id: true,
  email: true,
  role: true,
  firstName: true,
  lastName: true,
  fullName: true,
  phoneNumber: true,
  houseAddress: true,
  dateOfBirth: true,
  profilePhotoUrl: true,
  twoFactorEnabled: true,
  mustChangePassword: true,
  bankCode: true,
  bankName: true,
  accountNumber: true,
  accountName: true,
  referralCode: true,
} as const;

/// Unambiguous uppercase alphanumerics — no 0/O or 1/I, since this code
/// gets read aloud and typed by hand when someone shares an invite.
const _referralCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly notifications: NotificationsService,
  ) {}

  async findById(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: { ...profileSelect, createdAt: true },
    });
    if (!user) throw new NotFoundException('User not found');
    if (!user.referralCode) {
      user.referralCode = await this.assignReferralCode(id);
    }
    return user;
  }

  async updateProfile(id: string, dto: UpdateProfileDto) {
    const before = await this.prisma.user.findUniqueOrThrow({ where: { id } });

    let referredById = before.referredById;
    if (dto.referralCode && !before.referredById) {
      const code = dto.referralCode.trim().toUpperCase();
      const referrer = await this.prisma.user.findUnique({ where: { referralCode: code } });
      if (referrer && referrer.id !== id) {
        referredById = referrer.id;
      }
    }

    const { referralCode: _incomingReferralCode, ...profileFields } = dto;
    const updated = await this.prisma.user.update({
      where: { id },
      data: {
        ...profileFields,
        dateOfBirth: dto.dateOfBirth ? new Date(dto.dateOfBirth) : undefined,
        referredById,
      },
      select: profileSelect,
    });

    // Fires once, the first time this account has both a real name and an
    // inviter — for most signups that's this exact call (fullName is set
    // here, at profile completion, not at signup). See the User model's
    // referralNotifiedAt doc comment for why this can't double-fire.
    const justNamedThemselves = !before.fullName && dto.fullName;
    if (justNamedThemselves && referredById && !before.referralNotifiedAt) {
      await this.notifications.create(
        referredById,
        NotificationType.REFERRAL_SIGNUP,
        'Referral bonus!',
        `${dto.fullName} signed up for Home Servant using your referral code. Thanks for supporting the app by inviting friends!`,
      );
      await this.prisma.user.update({ where: { id }, data: { referralNotifiedAt: new Date() } });
    }

    return updated;
  }

  /// Re-resolves the account through Paystack server-side rather than
  /// trusting whatever account name the client's own earlier
  /// GET /paystack/resolve-account call showed the landlord — a client
  /// could otherwise submit a bank code/account number pair alongside a
  /// forged name and redirect where tenant payments get credited.
  async updateBankDetails(id: string, dto: UpdateBankDetailsDto) {
    const [{ accountName }, banks] = await Promise.all([
      this.paystack.resolveAccount(dto.accountNumber, dto.bankCode),
      this.paystack.listBanks(),
    ]);
    const bank = banks.find((b) => b.code === dto.bankCode);

    return this.prisma.user.update({
      where: { id },
      data: {
        bankCode: dto.bankCode,
        bankName: bank?.name ?? null,
        accountNumber: dto.accountNumber,
        accountName,
      },
      select: profileSelect,
    });
  }

  /// Backfills a referral code for an account that existed before this
  /// field did, instead of requiring a one-off data migration — generated
  /// lazily on first `GET /users/me` after this shipped.
  private async assignReferralCode(userId: string): Promise<string> {
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = this.generateReferralCode();
      try {
        await this.prisma.user.update({ where: { id: userId }, data: { referralCode: code } });
        return code;
      } catch {
        // Unique constraint collision — vanishingly unlikely at this
        // code space, but retry with a fresh code rather than fail.
      }
    }
    throw new InternalServerErrorException('Could not assign a referral code');
  }

  private generateReferralCode(): string {
    let suffix = '';
    for (let i = 0; i < 6; i++) {
      suffix += _referralCodeChars[Math.floor(Math.random() * _referralCodeChars.length)];
    }
    return `HS-${suffix}`;
  }
}
