import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ChatGateway } from '../chat/chat.gateway';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { CreateVendorProfileDto } from './dto/create-vendor-profile.dto';
import { UpdateVendorProfileDto } from './dto/update-vendor-profile.dto';

@Injectable()
export class VendorsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly storage: StorageService,
    private readonly chatGateway: ChatGateway,
  ) {}

  async create(userId: string, dto: CreateVendorProfileDto) {
    if (dto.logoUrl) await this.storage.assertIsOwnImage(dto.logoUrl);
    const existing = await this.prisma.vendorProfile.findUnique({ where: { userId } });
    if (existing) {
      throw new ConflictException('This account already has a vendor profile');
    }
    const profile = await this.prisma.vendorProfile.create({ data: { userId, ...dto } });
    // The admin console's Vendors nav badge (AdminShell._pendingVendorsCount)
    // only ever refreshed once, at console startup — without this, a new
    // application wouldn't show up there until the next login.
    this.chatGateway.broadcastToAdmins('admin:badges-changed', {});
    return profile;
  }

  async findMine(userId: string) {
    const profile = await this.prisma.vendorProfile.findUnique({ where: { userId } });
    if (!profile) throw new NotFoundException('No vendor profile for this account yet');
    return profile;
  }

  /// Re-resolves the account through Paystack server-side rather than
  /// trusting a client-supplied account name — exact same pattern as
  /// UsersService.updateBankDetails. [bankCode]/[accountNumber] only come
  /// through together (both or neither — see UpdateVendorProfileDto);
  /// every other field on the DTO (businessName/category/state/etc.)
  /// updates independently of whether bank details were also sent.
  async update(userId: string, dto: UpdateVendorProfileDto) {
    if (dto.logoUrl) await this.storage.assertIsOwnImage(dto.logoUrl);
    await this.findMine(userId);
    const { bankCode, accountNumber, ...rest } = dto;

    let bankFields: { bankCode: string; bankName: string | null; accountNumber: string; accountName: string } | undefined;
    if (bankCode && accountNumber) {
      const [{ accountName }, banks] = await Promise.all([
        this.paystack.resolveAccount(accountNumber, bankCode),
        this.paystack.listBanks(),
      ]);
      const bank = banks.find((b) => b.code === bankCode);
      bankFields = { bankCode, bankName: bank?.name ?? null, accountNumber, accountName };
    }

    return this.prisma.vendorProfile.update({ where: { userId }, data: { ...rest, ...bankFields } });
  }

  /// Used by ProductsService/OrdersService to resolve "the vendor profile
  /// belonging to this authenticated user" and enforce ownership — throws
  /// rather than returning null so callers don't need their own guard.
  async requireOwn(userId: string) {
    const profile = await this.prisma.vendorProfile.findUnique({ where: { userId } });
    if (!profile) throw new ForbiddenException('No vendor profile for this account');
    return profile;
  }
}
