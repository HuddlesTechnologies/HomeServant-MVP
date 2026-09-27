import { Injectable } from '@nestjs/common';
import { Prisma, VerificationStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/// The single PlatformSettings row (id 1), created with defaults on first read.
@Injectable()
export class PlatformSettingsService {
  constructor(private readonly prisma: PrismaService) {}

  async get() {
    const settings = await this.prisma.platformSettings.upsert({
      where: { id: 1 },
      create: { id: 1 },
      update: {},
      include: { updatedBy: { select: { id: true, fullName: true, email: true } } },
    });
    // What the switch affects, so a super admin can see the impact first.
    const active = { deactivatedAt: null };
    const [totalListings, unverifiedListings, verifiedLandlords, landlordsWithListings] = await Promise.all([
      this.prisma.property.count({ where: { landlord: active } }),
      this.prisma.property.count({
        where: { landlord: { ...active, NOT: PlatformSettingsService.verifiedLandlordFilter() } },
      }),
      this.prisma.user.count({ where: { role: 'LANDLORD', ...active, ...PlatformSettingsService.verifiedLandlordFilter() } }),
      this.prisma.user.count({ where: { role: 'LANDLORD', ...active, properties: { some: {} } } }),
    ]);
    return { ...settings, stats: { totalListings, unverifiedListings, verifiedLandlords, landlordsWithListings } };
  }

  async update(adminId: string, data: { requireVerifiedLandlords?: boolean }) {
    await this.prisma.platformSettings.upsert({
      where: { id: 1 },
      create: { id: 1, ...data, updatedById: adminId },
      update: { ...data, updatedById: adminId },
    });
    return this.get();
  }

  async requireVerifiedLandlords(): Promise<boolean> {
    const row = await this.prisma.platformSettings.findUnique({ where: { id: 1 }, select: { requireVerifiedLandlords: true } });
    return row?.requireVerifiedLandlords ?? false;
  }

  /// Property filter for "only verified landlords' listings".
  static verifiedLandlordFilter(): Prisma.UserWhereInput {
    return { identityVerification: { status: VerificationStatus.APPROVED } };
  }
}
