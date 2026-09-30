-- Admins can pause (and resume) or cancel a landlord payout.
ALTER TABLE "Payment" ADD COLUMN "payoutPausedAt" TIMESTAMP(3);
ALTER TABLE "Payment" ADD COLUMN "payoutPausedById" TEXT;
ALTER TABLE "Payment" ADD COLUMN "payoutPauseReason" TEXT;
ALTER TABLE "Payment" ADD COLUMN "payoutCancelledAt" TIMESTAMP(3);
ALTER TABLE "Payment" ADD COLUMN "payoutCancelledById" TEXT;
ALTER TABLE "Payment" ADD COLUMN "payoutCancelReason" TEXT;
