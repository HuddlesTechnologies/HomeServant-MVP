import { Injectable, NotFoundException } from '@nestjs/common';
import { PlatformSettingsService } from '../platform-settings/platform-settings.service';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class FavoritesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly platform: PlatformSettingsService,
  ) {}

  /// Saved listings stay in the wishlist even when Platform Controls hides
  /// them from browsing; the flags say so (see PlatformSettingsService).
  async findForUser(userId: string) {
    const [favorites, requireVerified] = await Promise.all([
      this.prisma.favorite.findMany({
        where: { userId },
        include: { property: { include: PlatformSettingsService.landlordStatusInclude } },
        orderBy: { createdAt: 'desc' },
      }),
      this.platform.requireVerifiedLandlords(),
    ]);
    return favorites.map(({ property: { landlord, ...property }, ...favorite }) => ({
      ...favorite,
      property: { ...property, ...PlatformSettingsService.listingFlags(landlord.identityVerification?.status, requireVerified) },
    }));
  }

  /// Toggles rather than a plain add — mirrors the Flutter client's
  /// `AppState.toggleFavorite`, so the app can call one endpoint on every
  /// heart tap without first checking current state.
  async toggle(userId: string, propertyId: string): Promise<{ favorited: boolean }> {
    const property = await this.prisma.property.findUnique({ where: { id: propertyId } });
    if (!property) throw new NotFoundException('Property not found');

    const existing = await this.prisma.favorite.findUnique({
      where: { userId_propertyId: { userId, propertyId } },
    });

    if (existing) {
      await this.prisma.favorite.delete({ where: { id: existing.id } });
      return { favorited: false };
    }

    await this.prisma.favorite.create({ data: { userId, propertyId } });
    return { favorited: true };
  }
}
