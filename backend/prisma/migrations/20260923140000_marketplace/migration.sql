-- AlterEnum
ALTER TYPE "UserRole" ADD VALUE 'VENDOR';

-- CreateEnum
CREATE TYPE "MarketplaceCategory" AS ENUM ('FURNITURE', 'HOME_APPLIANCES', 'ELECTRONICS', 'FITTINGS_FIXTURES', 'DECOR', 'TOOLS_EQUIPMENT', 'OTHER');

-- CreateEnum
CREATE TYPE "FulfillmentMethod" AS ENUM ('DELIVERY', 'PICKUP');

-- CreateEnum
CREATE TYPE "MarketplacePaymentMethod" AS ENUM ('CARD', 'BANK_TRANSFER');

-- CreateEnum
CREATE TYPE "OrderItemStatus" AS ENUM ('PENDING', 'COMPLETED', 'CANCELLED');

-- CreateTable
CREATE TABLE "VendorProfile" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "businessName" TEXT NOT NULL,
    "category" "MarketplaceCategory" NOT NULL,
    "state" TEXT NOT NULL,
    "rcNumber" TEXT,
    "logoUrl" TEXT,
    "bankName" TEXT,
    "accountNumber" TEXT,
    "accountName" TEXT,
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "VendorProfile_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Product" (
    "id" TEXT NOT NULL,
    "vendorId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "price" INTEGER NOT NULL,
    "stock" INTEGER NOT NULL,
    "category" "MarketplaceCategory" NOT NULL,
    "imageUrls" TEXT[] DEFAULT ARRAY[]::TEXT[],
    "videoUrl" TEXT,
    "fulfillmentOptions" "FulfillmentMethod"[] DEFAULT ARRAY[]::"FulfillmentMethod"[],
    "isAvailable" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Product_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MarketplaceOrder" (
    "id" TEXT NOT NULL,
    "buyerId" TEXT NOT NULL,
    "paymentMethod" "MarketplacePaymentMethod" NOT NULL,
    "customerName" TEXT NOT NULL,
    "customerPhone" TEXT NOT NULL,
    "customerAddress" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MarketplaceOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "MarketplaceOrderItem" (
    "id" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "vendorId" TEXT NOT NULL,
    "productName" TEXT NOT NULL,
    "unitPrice" INTEGER NOT NULL,
    "quantity" INTEGER NOT NULL,
    "fulfillment" "FulfillmentMethod" NOT NULL,
    "status" "OrderItemStatus" NOT NULL DEFAULT 'PENDING',
    "notificationRead" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "MarketplaceOrderItem_pkey" PRIMARY KEY ("id")
);

-- AlterTable
ALTER TABLE "Thread" ADD COLUMN "orderId" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "VendorProfile_userId_key" ON "VendorProfile"("userId");

-- CreateIndex
CREATE INDEX "VendorProfile_category_idx" ON "VendorProfile"("category");

-- CreateIndex
CREATE INDEX "Product_vendorId_idx" ON "Product"("vendorId");

-- CreateIndex
CREATE INDEX "Product_category_idx" ON "Product"("category");

-- CreateIndex
CREATE INDEX "MarketplaceOrder_buyerId_idx" ON "MarketplaceOrder"("buyerId");

-- CreateIndex
CREATE INDEX "MarketplaceOrderItem_orderId_idx" ON "MarketplaceOrderItem"("orderId");

-- CreateIndex
CREATE INDEX "MarketplaceOrderItem_vendorId_idx" ON "MarketplaceOrderItem"("vendorId");

-- CreateIndex
CREATE INDEX "Thread_orderId_idx" ON "Thread"("orderId");

-- AddForeignKey
ALTER TABLE "VendorProfile" ADD CONSTRAINT "VendorProfile_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Product" ADD CONSTRAINT "Product_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "VendorProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MarketplaceOrder" ADD CONSTRAINT "MarketplaceOrder_buyerId_fkey" FOREIGN KEY ("buyerId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MarketplaceOrderItem" ADD CONSTRAINT "MarketplaceOrderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "MarketplaceOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MarketplaceOrderItem" ADD CONSTRAINT "MarketplaceOrderItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "Product"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MarketplaceOrderItem" ADD CONSTRAINT "MarketplaceOrderItem_vendorId_fkey" FOREIGN KEY ("vendorId") REFERENCES "VendorProfile"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Thread" ADD CONSTRAINT "Thread_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "MarketplaceOrder"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- RowLevelSecurity (see the earlier enable_rls migration's note — this
-- backend connects as the table owner, which RLS doesn't restrict; this
-- only closes off Supabase's public Data API for these new tables)
ALTER TABLE "VendorProfile" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Product" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "MarketplaceOrder" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "MarketplaceOrderItem" ENABLE ROW LEVEL SECURITY;
