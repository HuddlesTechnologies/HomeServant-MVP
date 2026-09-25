-- CreateEnum
CREATE TYPE "Gender" AS ENUM ('MALE', 'FEMALE', 'OTHER');

-- CreateEnum
CREATE TYPE "MaritalStatus" AS ENUM ('SINGLE', 'MARRIED', 'DIVORCED', 'WIDOWED');

-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "BookingStatus" ADD VALUE 'PAID_AWAITING_INSPECTION';
ALTER TYPE "BookingStatus" ADD VALUE 'INSPECTION_PROPOSED';
ALTER TYPE "BookingStatus" ADD VALUE 'INSPECTION_CONFIRMED';

-- AlterTable
ALTER TABLE "MarketplaceOrderItem" ADD COLUMN     "shippedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "gender" "Gender",
ADD COLUMN     "maritalStatus" "MaritalStatus",
ADD COLUMN     "occupation" TEXT;
