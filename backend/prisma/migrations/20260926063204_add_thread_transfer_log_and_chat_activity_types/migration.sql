-- AlterEnum
-- This migration adds more than one value to an enum.
-- With PostgreSQL versions 11 and earlier, this is not possible
-- in a single migration. This can be worked around by creating
-- multiple migrations, each migration adding only one value to
-- the enum.


ALTER TYPE "ActivityLogType" ADD VALUE 'SUPPORT_THREAD_CLAIMED';
ALTER TYPE "ActivityLogType" ADD VALUE 'SUPPORT_THREAD_TRANSFERRED';
ALTER TYPE "ActivityLogType" ADD VALUE 'SUPPORT_THREAD_RESOLVED';

-- CreateTable
CREATE TABLE "ThreadTransferLog" (
    "id" TEXT NOT NULL,
    "threadId" TEXT NOT NULL,
    "fromAdminId" TEXT,
    "toAdminId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ThreadTransferLog_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ThreadTransferLog_threadId_idx" ON "ThreadTransferLog"("threadId");

-- AddForeignKey
ALTER TABLE "ThreadTransferLog" ADD CONSTRAINT "ThreadTransferLog_threadId_fkey" FOREIGN KEY ("threadId") REFERENCES "Thread"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ThreadTransferLog" ADD CONSTRAINT "ThreadTransferLog_fromAdminId_fkey" FOREIGN KEY ("fromAdminId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ThreadTransferLog" ADD CONSTRAINT "ThreadTransferLog_toAdminId_fkey" FOREIGN KEY ("toAdminId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
