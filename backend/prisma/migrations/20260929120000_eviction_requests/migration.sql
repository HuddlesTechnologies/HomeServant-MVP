-- CreateEnum
CREATE TYPE "EvictionStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED');

-- CreateTable
CREATE TABLE "EvictionRequest" (
    "id" TEXT NOT NULL,
    "bookingId" TEXT NOT NULL,
    "landlordId" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "tenantResponse" TEXT,
    "tenantRespondedAt" TIMESTAMP(3),
    "status" "EvictionStatus" NOT NULL DEFAULT 'PENDING',
    "reviewedById" TEXT,
    "reviewNote" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "EvictionRequest_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "EvictionRequest_bookingId_idx" ON "EvictionRequest"("bookingId");

-- CreateIndex
CREATE INDEX "EvictionRequest_status_idx" ON "EvictionRequest"("status");

-- CreateIndex
CREATE INDEX "EvictionRequest_landlordId_idx" ON "EvictionRequest"("landlordId");

-- CreateIndex
CREATE INDEX "EvictionRequest_tenantId_idx" ON "EvictionRequest"("tenantId");

-- AddForeignKey
ALTER TABLE "EvictionRequest" ADD CONSTRAINT "EvictionRequest_bookingId_fkey" FOREIGN KEY ("bookingId") REFERENCES "Booking"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EvictionRequest" ADD CONSTRAINT "EvictionRequest_landlordId_fkey" FOREIGN KEY ("landlordId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EvictionRequest" ADD CONSTRAINT "EvictionRequest_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "EvictionRequest" ADD CONSTRAINT "EvictionRequest_reviewedById_fkey" FOREIGN KEY ("reviewedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

