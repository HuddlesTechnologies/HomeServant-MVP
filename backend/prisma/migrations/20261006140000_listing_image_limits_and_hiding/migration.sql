-- Limits on how often a landlord can change a listing's photos, and
-- landlord-hidden listings.
ALTER TABLE "Property" ADD COLUMN "imageChangesUsed" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN "imagesLockedUntil" TIMESTAMP(3),
ADD COLUMN "hiddenByLandlordAt" TIMESTAMP(3);

ALTER TABLE "PlatformSettings" ADD COLUMN "maxListingImageChanges" INTEGER NOT NULL DEFAULT 3,
ADD COLUMN "listingImageLockDays" INTEGER NOT NULL DEFAULT 14;
