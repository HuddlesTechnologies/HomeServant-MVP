-- Calls admins place to customers from a chat, with the reason given.
ALTER TYPE "ActivityLogType" ADD VALUE 'SUPPORT_CUSTOMER_CALLED';
ALTER TYPE "ActivityLogType" ADD VALUE 'ADMIN_USER_BANNED';
ALTER TYPE "ActivityLogType" ADD VALUE 'ADMIN_USER_UNBANNED';
ALTER TYPE "ActivityLogType" ADD VALUE 'ADMIN_PROPERTY_BOOSTED';

CREATE TABLE "SupportCallLog" (
    "id" TEXT NOT NULL,
    "threadId" TEXT NOT NULL,
    "adminId" TEXT,
    "customerId" TEXT,
    "phoneNumber" TEXT NOT NULL,
    "reason" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SupportCallLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "SupportCallLog_threadId_idx" ON "SupportCallLog"("threadId");

ALTER TABLE "SupportCallLog" ADD CONSTRAINT "SupportCallLog_threadId_fkey" FOREIGN KEY ("threadId") REFERENCES "Thread"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SupportCallLog" ADD CONSTRAINT "SupportCallLog_adminId_fkey" FOREIGN KEY ("adminId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "SupportCallLog" ADD CONSTRAINT "SupportCallLog_customerId_fkey" FOREIGN KEY ("customerId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
