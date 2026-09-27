-- AlterTable
ALTER TABLE "User" ADD COLUMN "adminOnDuty" BOOLEAN NOT NULL DEFAULT true;

-- AlterTable
ALTER TABLE "Thread" ADD COLUMN "unclaimedReminderAt" TIMESTAMP(3),
ADD COLUMN "replyEscalatedAt" TIMESTAMP(3);
