import { randomBytes } from 'crypto';
import { BadRequestException, ForbiddenException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { NotificationType, PropertyCategory } from '@prisma/client';
import { NotificationsService } from '../notifications/notifications.service';
import { PaystackService } from '../paystack/paystack.service';
import { PlatformSettingsService } from '../platform-settings/platform-settings.service';
import { PrismaService } from '../prisma/prisma.service';

const DAY_MS = 24 * 60 * 60 * 1000;

/// Landlords' paid "Featured" ads (see ListingPromotion). The price and
/// length come from Platform Controls; payment goes through Paystack's
/// hosted checkout like rent does, but the fee is HomeServant's own — no
/// escrow, no payout. The ad starts when Paystack confirms the charge (or
/// when an ad already running on the listing ends).
@Injectable()
export class PromotionsService {
  private readonly logger = new Logger('Promotions');

  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly platform: PlatformSettingsService,
    private readonly notifications: NotificationsService,
  ) {}

  /// What featuring [propertyId] costs now, and until when it would run.
  async quote(propertyId: string, landlordId: string) {
    await this.ownedListing(propertyId, landlordId);
    const price = await this.platform.featuredListingPrice();
    const runningUntil = await this.runningUntil(propertyId);
    const startsAt = runningUntil ?? new Date();
    return {
      feeNaira: price.feeNaira,
      days: price.days,
      featuredUntil: runningUntil,
      wouldRunUntil: new Date(startsAt.getTime() + price.days * DAY_MS),
    };
  }

  /// Starts checkout for a featured ad on the landlord's own listing.
  /// Refused for a hidden listing, and for an occupied rental (it isn't in
  /// search, so an ad would buy nothing).
  async start(propertyId: string, landlordId: string) {
    const property = await this.ownedListing(propertyId, landlordId);
    if (property.hiddenByLandlordAt) {
      throw new BadRequestException('Show this listing to tenants again before featuring it.');
    }
    if (property.category !== PropertyCategory.SHORTLET && property.isOccupied) {
      throw new BadRequestException("This listing is occupied, so it isn't shown in search — there's nothing to feature right now.");
    }
    const landlord = await this.prisma.user.findUniqueOrThrow({ where: { id: landlordId }, select: { email: true } });
    const price = await this.platform.featuredListingPrice();
    const amountKobo = price.feeNaira * 100;
    const reference = `promo_${Date.now()}_${randomBytes(6).toString('hex')}`;

    // An earlier checkout that was never finished is superseded.
    await this.prisma.listingPromotion.updateMany({
      where: { propertyId, status: 'PENDING_PAYMENT' },
      data: { status: 'FAILED' },
    });
    await this.prisma.listingPromotion.create({
      data: { propertyId, landlordId, days: price.days, amountKobo, paystackReference: reference },
    });
    try {
      const init = await this.paystack.initializeTransaction(landlord.email, amountKobo, reference, {
        propertyId,
        purpose: 'FEATURED_LISTING',
      });
      return { reference: init.reference, authorizationUrl: init.authorizationUrl, feeNaira: price.feeNaira, days: price.days };
    } catch (error) {
      await this.prisma.listingPromotion.update({ where: { paystackReference: reference }, data: { status: 'FAILED' } });
      throw error;
    }
  }

  /// Paystack confirmed the charge for [reference]. Returns false when the
  /// reference isn't a featured-ad checkout (it belongs to rent or an
  /// order), true when handled. Idempotent: only the first delivery for a
  /// pending checkout activates it.
  async handleChargeSuccess(reference: string): Promise<boolean> {
    const promo = await this.prisma.listingPromotion.findUnique({ where: { paystackReference: reference } });
    if (!promo) return false;
    const now = new Date();
    // Extends any ad already running on the listing rather than overlapping it.
    const runningUntil = await this.runningUntil(promo.propertyId);
    const startsAt = runningUntil && runningUntil > now ? runningUntil : now;
    const endsAt = new Date(startsAt.getTime() + promo.days * DAY_MS);
    const { count } = await this.prisma.listingPromotion.updateMany({
      // A checkout marked FAILED because a newer one started still gets its
      // ad if the landlord did pay for it after all.
      where: { id: promo.id, status: { in: ['PENDING_PAYMENT', 'FAILED'] } },
      data: { status: 'ACTIVE', paidAt: now, startsAt, endsAt },
    });
    if (count === 0) return true;
    const property = await this.prisma.property.findUnique({ where: { id: promo.propertyId }, select: { title: true } });
    await this.notifications.create(
      promo.landlordId,
      NotificationType.BOOKING_STATUS,
      'Your listing is featured',
      `${property?.title ?? 'Your listing'} is featured until ${endsAt.toDateString()}. Tenants see it marked "Featured" in search.`,
    );
    this.logger.log(`Featured ad ${promo.id} active ${startsAt.toISOString()} → ${endsAt.toISOString()}`);
    return true;
  }

  /// The landlord's paid ads on [propertyId], newest first.
  async history(propertyId: string, landlordId: string) {
    await this.ownedListing(propertyId, landlordId);
    return this.prisma.listingPromotion.findMany({
      where: { propertyId, status: 'ACTIVE' },
      orderBy: { createdAt: 'desc' },
      select: { id: true, days: true, amountKobo: true, paidAt: true, startsAt: true, endsAt: true },
    });
  }

  /// When the ads already paid for on [propertyId] run out (null if none
  /// is running or queued).
  private async runningUntil(propertyId: string): Promise<Date | null> {
    const latest = await this.prisma.listingPromotion.findFirst({
      where: { propertyId, status: 'ACTIVE', endsAt: { gt: new Date() } },
      orderBy: { endsAt: 'desc' },
      select: { endsAt: true },
    });
    return latest?.endsAt ?? null;
  }

  private async ownedListing(propertyId: string, landlordId: string) {
    const property = await this.prisma.property.findUnique({ where: { id: propertyId } });
    if (!property) throw new NotFoundException('Property not found');
    if (property.landlordId !== landlordId) throw new ForbiddenException('You do not own this property');
    return property;
  }
}
