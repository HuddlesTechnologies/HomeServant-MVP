-- AlterTable
ALTER TABLE "Payment" ADD COLUMN     "heldForVerificationAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "PlatformSettings" ADD COLUMN     "payUnverifiedLandlords" BOOLEAN NOT NULL DEFAULT true;

