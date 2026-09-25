-- CreateEnum
CREATE TYPE "PaymentPurpose" AS ENUM ('RENTAL_BOOKING', 'MARKETPLACE_ORDER_ITEM');

-- CreateEnum
CREATE TYPE "PaymentStatus" AS ENUM ('INITIATED', 'PAID_HELD', 'RELEASED', 'REFUNDED', 'FAILED');

-- CreateEnum
CREATE TYPE "MessageType" AS ENUM ('TEXT', 'PROPERTY_PREVIEW');

-- AlterEnum
ALTER TYPE "ActivityLogType" ADD VALUE 'ADMIN_USER_EDITED';

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "BookingStatus" ADD VALUE 'PAID';
ALTER TYPE "BookingStatus" ADD VALUE 'MOVED_IN';
ALTER TYPE "BookingStatus" ADD VALUE 'REFUNDED';

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "NotificationType" ADD VALUE 'VENDOR_SUSPENDED';
ALTER TYPE "NotificationType" ADD VALUE 'VENDOR_UNSUSPENDED';
ALTER TYPE "NotificationType" ADD VALUE 'RENT_EXPIRY_REMINDER';
ALTER TYPE "NotificationType" ADD VALUE 'NEW_LISTING_MESSAGE';

-- DropForeignKey
ALTER TABLE "Message" DROP CONSTRAINT "Message_senderId_fkey";

-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "inspectionConfirmedAt" TIMESTAMP(3),
ADD COLUMN     "leaseEndDate" TIMESTAMP(3),
ADD COLUMN     "leaseStartDate" TIMESTAMP(3),
ADD COLUMN     "priceSnapshot" INTEGER,
ADD COLUMN     "priceUnitSnapshot" "PriceUnit";

-- AlterTable
ALTER TABLE "Message" ADD COLUMN     "previewPropertyImageUrl" TEXT,
ADD COLUMN     "previewPropertyPrice" INTEGER,
ADD COLUMN     "previewPropertyPriceUnit" "PriceUnit",
ADD COLUMN     "previewPropertyTitle" TEXT,
ADD COLUMN     "type" "MessageType" NOT NULL DEFAULT 'TEXT',
ALTER COLUMN "senderId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "Product" ALTER COLUMN "fulfillmentOptions" DROP DEFAULT;

-- AlterTable
ALTER TABLE "Property" ADD COLUMN     "messagingEnabled" BOOLEAN NOT NULL DEFAULT true,
ADD COLUMN     "rentDurationMonths" INTEGER,
ADD COLUMN     "roomNumber" TEXT,
ADD COLUMN     "unitAddress" TEXT;

-- AlterTable
ALTER TABLE "VendorProfile" ADD COLUMN     "bankCode" TEXT;

-- CreateTable
CREATE TABLE "Payment" (
    "id" TEXT NOT NULL,
    "purpose" "PaymentPurpose" NOT NULL,
    "bookingId" TEXT,
    "orderItemId" TEXT,
    "payerId" TEXT NOT NULL,
    "recipientUserId" TEXT NOT NULL,
    "amount" INTEGER NOT NULL,
    "platformFeeAmount" INTEGER NOT NULL,
    "paystackReference" TEXT NOT NULL,
    "transferRecipientCode" TEXT,
    "status" "PaymentStatus" NOT NULL DEFAULT 'INITIATED',
    "paidAt" TIMESTAMP(3),
    "releasedAt" TIMESTAMP(3),
    "refundedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Payment_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TenancyAgreement" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "propertyTitle" TEXT NOT NULL,
    "propertyLocation" TEXT NOT NULL,
    "propertyState" TEXT NOT NULL,
    "rentAmount" INTEGER NOT NULL,
    "priceUnit" "PriceUnit" NOT NULL,
    "leaseStartDate" TIMESTAMP(3) NOT NULL,
    "leaseEndDate" TIMESTAMP(3) NOT NULL,
    "landlordName" TEXT NOT NULL,
    "landlordEmail" TEXT NOT NULL,
    "landlordPhone" TEXT,
    "tenantName" TEXT NOT NULL,
    "tenantEmail" TEXT NOT NULL,
    "tenantPhone" TEXT,
    "generatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TenancyAgreement_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Payment_orderItemId_key" ON "Payment"("orderItemId");

-- CreateIndex
CREATE UNIQUE INDEX "Payment_paystackReference_key" ON "Payment"("paystackReference");

-- CreateIndex
CREATE INDEX "Payment_bookingId_idx" ON "Payment"("bookingId");

-- CreateIndex
CREATE INDEX "Payment_status_idx" ON "Payment"("status");

-- CreateIndex
CREATE UNIQUE INDEX "TenancyAgreement_bookingId_key" ON "TenancyAgreement"("bookingId");

-- CreateIndex
CREATE INDEX "Booking_leaseEndDate_idx" ON "Booking"("leaseEndDate");

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_orderItemId_fkey" FOREIGN KEY ("orderItemId") REFERENCES "MarketplaceOrderItem"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_payerId_fkey" FOREIGN KEY ("payerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Payment" ADD CONSTRAINT "Payment_recipientUserId_fkey" FOREIGN KEY ("recipientUserId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Message" ADD CONSTRAINT "Message_senderId_fkey" FOREIGN KEY ("senderId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TenancyAgreement" ADD CONSTRAINT "TenancyAgreement_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE CASCADE ON UPDATE CASCADE;
