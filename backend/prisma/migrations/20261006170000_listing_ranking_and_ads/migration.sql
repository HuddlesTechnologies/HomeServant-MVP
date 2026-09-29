-- Admin search ranking and landlords' paid "Featured" ads.
ALTER TABLE "Property" ADD COLUMN "adminBoost" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "adminBoostUntil" TIMESTAMP(3);

ALTER TABLE "PlatformSettings" ADD COLUMN "featuredListingFeeNaira" INTEGER NOT NULL DEFAULT 5000,
ADD COLUMN "featuredListingDays" INTEGER NOT NULL DEFAULT 7,
ADD COLUMN "promotedSlotEvery" INTEGER NOT NULL DEFAULT 3;

CREATE TYPE "PromotionStatus" AS ENUM ('PENDING_PAYMENT', 'ACTIVE', 'FAILED');

CREATE TABLE "ListingPromotion" (
    "id" TEXT NOT NULL,
    "propertyId" TEXT NOT NULL,
    "landlordId" TEXT NOT NULL,
    "days" INTEGER NOT NULL,
    "amountKobo" INTEGER NOT NULL,
    "paystackReference" TEXT NOT NULL,
    "status" "PromotionStatus" NOT NULL DEFAULT 'PENDING_PAYMENT',
    "paidAt" TIMESTAMP(3),
    "startsAt" TIMESTAMP(3),
    "endsAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ListingPromotion_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ListingPromotion_paystackReference_key" ON "ListingPromotion"("paystackReference");
CREATE INDEX "ListingPromotion_propertyId_status_idx" ON "ListingPromotion"("propertyId", "status");

ALTER TABLE "ListingPromotion" ADD CONSTRAINT "ListingPromotion_propertyId_fkey" FOREIGN KEY ("propertyId") REFERENCES "Property"("id") ON DELETE CASCADE ON UPDATE CASCADE;
