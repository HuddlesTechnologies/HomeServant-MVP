-- Permanent bans (a super admin can lift them).
ALTER TABLE "User" ADD COLUMN "bannedAt" TIMESTAMP(3),
ADD COLUMN "banReason" TEXT,
ADD COLUMN "bannedById" TEXT;

CREATE INDEX "User_bannedAt_idx" ON "User"("bannedAt");

ALTER TYPE "NotificationType" ADD VALUE 'ACCOUNT_BANNED';
ALTER TYPE "NotificationType" ADD VALUE 'ACCOUNT_UNBANNED';
