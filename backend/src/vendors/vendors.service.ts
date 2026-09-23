import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateVendorProfileDto } from './dto/create-vendor-profile.dto';
import { UpdateVendorProfileDto } from './dto/update-vendor-profile.dto';

@Injectable()
export class VendorsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(userId: string, dto: CreateVendorProfileDto) {
    const existing = await this.prisma.vendorProfile.findUnique({ where: { userId } });
    if (existing) {
      throw new ConflictException('This account already has a vendor profile');
    }
    return this.prisma.vendorProfile.create({ data: { userId, ...dto } });
  }

  async findMine(userId: string) {
    const profile = await this.prisma.vendorProfile.findUnique({ where: { userId } });
    if (!profile) throw new NotFoundException('No vendor profile for this account yet');
    return profile;
  }

  async update(userId: string, dto: UpdateVendorProfileDto) {
    await this.findMine(userId);
    return this.prisma.vendorProfile.update({ where: { userId }, data: dto });
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
