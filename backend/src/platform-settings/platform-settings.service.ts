import { Injectable, Logger } from '@nestjs/common';
import { NotificationType, Prisma, UserRole, VerificationStatus } from '@prisma/client';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PrismaService } from '../prisma/prisma.service';
import { escapeHtml } from '../common/escape-html';

/// The single PlatformSettings row (id 1), created with defaults on first read.
@Injectable()
export class PlatformSettingsService {
  private readonly logger = new Logger('PlatformSettings');

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
  ) {}

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

  async update(
    adminId: string,
    data: {
      requireVerifiedLandlords?: boolean;
      payUnverifiedLandlords?: boolean;
      maxListingImageChanges?: number;
      listingImageLockDays?: number;
      featuredListingFeeNaira?: number;
      featuredListingDays?: number;
      promotedSlotEvery?: number;
    },
  ) {
    const before = await this.requireVerifiedLandlords();
    await this.prisma.platformSettings.upsert({
      where: { id: 1 },
      create: { id: 1, ...data, updatedById: adminId },
      update: { ...data, updatedById: adminId },
    });
    if (!before && data.requireVerifiedLandlords === true) {
      // Background: a large landlord list must not hold up the toggle.
      void this.notifyUnverifiedLandlords().catch((error) =>
        this.logger.error(`Could not notify unverified landlords: ${(error as Error).message}`),
      );
    }
    return this.get();
  }

  /// When "Only verified landlords" is switched on: every active landlord
  /// with listings who isn't verified yet is told their listings are now
  /// hidden and how to fix it. Returns how many were told.
  async notifyUnverifiedLandlords(): Promise<number> {
    const landlords = await this.prisma.user.findMany({
      where: {
        role: UserRole.LANDLORD,
        deactivatedAt: null,
        properties: { some: {} },
        NOT: PlatformSettingsService.verifiedLandlordFilter(),
      },
      select: { id: true, email: true, fullName: true, identityVerification: { select: { status: true } } },
    });
    for (const landlord of landlords) {
      const status = landlord.identityVerification?.status;
      const next =
        status === VerificationStatus.PENDING
          ? 'Your documents are already with us for review; your listings will reappear as soon as you are verified.'
          : status === VerificationStatus.REJECTED
            ? 'Your last submission was not accepted. Open your Profile in the app to see what to fix and resubmit.'
            : 'Open your Profile in the app and tap "Get verified" to submit your ID and ownership documents.';
      const body = `HomeServant now only shows listings from verified landlords, so your listings are hidden from tenants. ${next} Your current tenants and bookings are not affected.`;
      await this.notifications.create(landlord.id, NotificationType.BOOKING_STATUS, 'Get verified to show your listings', body);
      await this.mail.send(
        landlord.email,
        'Get verified to keep your listings visible on HomeServant',
        `<p>Hi${landlord.fullName ? ` ${escapeHtml(landlord.fullName)}` : ''},</p><p>${escapeHtml(body)}</p>`,
        body,
      );
    }
    this.logger.log(`Told ${landlords.length} unverified landlord(s) their listings are hidden`);
    return landlords.length;
  }

  /// Default true (pay everyone) when the row doesn't exist yet.
  async payUnverifiedLandlords(): Promise<boolean> {
    const row = await this.prisma.platformSettings.findUnique({ where: { id: 1 }, select: { payUnverifiedLandlords: true } });
    return row?.payUnverifiedLandlords ?? true;
  }

  /// How many photo changes a listing gets before they lock, and for how
  /// long (see Property.imageChangesUsed). Defaults when the row is missing.
  async listingImageRules(): Promise<{ maxChanges: number; lockDays: number }> {
    const row = await this.prisma.platformSettings.findUnique({
      where: { id: 1 },
      select: { maxListingImageChanges: true, listingImageLockDays: true },
    });
    return { maxChanges: row?.maxListingImageChanges ?? 3, lockDays: row?.listingImageLockDays ?? 14 };
  }

  /// Fairness: one promoted listing in every N search results (min 2).
  async promotedSlotEvery(): Promise<number> {
    const row = await this.prisma.platformSettings.findUnique({ where: { id: 1 }, select: { promotedSlotEvery: true } });
    return Math.max(2, row?.promotedSlotEvery ?? 3);
  }

  /// What a paid "Featured" ad costs (naira) and how many days it runs.
  async featuredListingPrice(): Promise<{ feeNaira: number; days: number }> {
    const row = await this.prisma.platformSettings.findUnique({
      where: { id: 1 },
      select: { featuredListingFeeNaira: true, featuredListingDays: true },
    });
    return { feeNaira: row?.featuredListingFeeNaira ?? 5000, days: row?.featuredListingDays ?? 7 };
  }

  async requireVerifiedLandlords(): Promise<boolean> {
    const row = await this.prisma.platformSettings.findUnique({ where: { id: 1 }, select: { requireVerifiedLandlords: true } });
    return row?.requireVerifiedLandlords ?? false;
  }

  /// The two listing flags every property response carries: whether its
  /// landlord is verified (badge), and whether Platform Controls is hiding
  /// it from browsing because they aren't (so a tenant who already booked
  /// it, or saved it, can be told why it no longer shows up).
  static listingFlags(landlordStatus: VerificationStatus | null | undefined, requireVerified: boolean) {
    const landlordVerified = landlordStatus === VerificationStatus.APPROVED;
    return { landlordVerified, hiddenUntilLandlordVerified: requireVerified && !landlordVerified };
  }

  /// Property include that fetches just the landlord's verification status.
  static readonly landlordStatusInclude = {
    landlord: { select: { identityVerification: { select: { status: true } } } },
  } as const;

  /// Property filter for "only verified landlords' listings".
  static verifiedLandlordFilter(): Prisma.UserWhereInput {
    return { identityVerification: { status: VerificationStatus.APPROVED } };
  }
}

