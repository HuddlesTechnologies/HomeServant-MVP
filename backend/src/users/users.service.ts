import { Injectable, NotFoundException } from '@nestjs/common';
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
  bankCode: true,
  bankName: true,
  accountNumber: true,
  accountName: true,
} as const;

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
  ) {}

  async findById(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: { ...profileSelect, createdAt: true },
    });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async updateProfile(id: string, dto: UpdateProfileDto) {
    return this.prisma.user.update({
      where: { id },
      data: { ...dto, dateOfBirth: dto.dateOfBirth ? new Date(dto.dateOfBirth) : undefined },
      select: profileSelect,
    });
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
}
