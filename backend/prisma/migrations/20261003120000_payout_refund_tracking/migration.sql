-- AlterTable
ALTER TABLE "Payment" ADD COLUMN     "moneyLockedAt" TIMESTAMP(3),
ADD COLUMN     "payoutAttempts" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "payoutLastAttemptAt" TIMESTAMP(3),
ADD COLUMN     "payoutLastError" TEXT,
ADD COLUMN     "payoutReference" TEXT,
ADD COLUMN     "refundLastAttemptAt" TIMESTAMP(3),
ADD COLUMN     "refundLastError" TEXT,
ADD COLUMN     "refundReason" TEXT,
ADD COLUMN     "refundRequestedAmount" INTEGER,
ADD COLUMN     "refundRequestedBy" TEXT,
ADD COLUMN     "refundedById" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "Payment_payoutReference_key" ON "Payment"("payoutReference");

