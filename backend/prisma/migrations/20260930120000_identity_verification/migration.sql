-- CreateEnum
CREATE TYPE "IdType" AS ENUM ('NIN', 'DRIVERS_LICENSE', 'VOTERS_CARD', 'INTERNATIONAL_PASSPORT');

-- CreateEnum
CREATE TYPE "VerificationStatus" AS ENUM ('INCOMPLETE', 'PENDING', 'APPROVED', 'REJECTED');

-- CreateTable
CREATE TABLE "IdentityVerification" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "idType" "IdType",
    "idNumber" TEXT,
    "certificatePath" TEXT,
    "documentPath" TEXT,
    "status" "VerificationStatus" NOT NULL DEFAULT 'INCOMPLETE',
    "submittedAt" TIMESTAMP(3),
    "reviewedById" TEXT,
    "reviewNote" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IdentityVerification_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "IdentityVerification_userId_key" ON "IdentityVerification"("userId");

-- CreateIndex
CREATE INDEX "IdentityVerification_status_idx" ON "IdentityVerification"("status");

-- AddForeignKey
ALTER TABLE "IdentityVerification" ADD CONSTRAINT "IdentityVerification_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IdentityVerification" ADD CONSTRAINT "IdentityVerification_reviewedById_fkey" FOREIGN KEY ("reviewedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

