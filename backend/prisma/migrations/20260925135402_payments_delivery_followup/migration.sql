-- AlterTable
ALTER TABLE "Booking" ADD COLUMN     "lastRentReminderDaysOut" INTEGER,
ADD COLUMN     "nights" INTEGER;

-- AlterTable
ALTER TABLE "MarketplaceOrderItem" ADD COLUMN     "shipmentId" TEXT,
ADD COLUMN     "trackingNumber" TEXT;
