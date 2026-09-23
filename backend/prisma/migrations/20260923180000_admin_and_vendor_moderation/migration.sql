-- AlterEnum
ALTER TYPE "UserRole" ADD VALUE 'ADMIN';

-- AlterEnum
ALTER TYPE "NotificationType" ADD VALUE 'VENDOR_APPROVED';
ALTER TYPE "NotificationType" ADD VALUE 'VENDOR_REJECTED';
ALTER TYPE "NotificationType" ADD VALUE 'BOOKING_STATUS';
ALTER TYPE "NotificationType" ADD VALUE 'MARKETPLACE_ORDER_STATUS';
ALTER TYPE "NotificationType" ADD VALUE 'NEW_MESSAGE';

-- CreateEnum
CREATE TYPE "VendorApplicationStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- AlterTable
ALTER TABLE "VendorProfile" ADD COLUMN     "status" "VendorApplicationStatus" NOT NULL DEFAULT 'PENDING',
ADD COLUMN     "rejectionReason" TEXT;

-- Backfill: every vendor that existed before this migration was already
-- operating under the old "active immediately on signup" model — mark
-- them APPROVED so none of them silently disappear from the public feed
-- once that's gated on status (see MarketplaceProductsService).
UPDATE "VendorProfile" SET "status" = 'APPROVED';

-- CreateIndex
CREATE INDEX "VendorProfile_status_idx" ON "VendorProfile"("status");
