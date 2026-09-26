-- CreateEnum
CREATE TYPE "ThreadStatus" AS ENUM ('OPEN', 'RESOLVED');

-- AlterTable
ALTER TABLE "Thread" ADD COLUMN     "assignedAdminId" TEXT,
ADD COLUMN     "isSupport" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "resolvedAt" TIMESTAMP(3),
ADD COLUMN     "status" "ThreadStatus" NOT NULL DEFAULT 'OPEN';

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "lastActiveAt" TIMESTAMP(3),
ADD COLUMN     "lastLoginDeviceModel" TEXT,
ADD COLUMN     "lastLoginIp" TEXT;

-- CreateIndex
CREATE INDEX "Thread_isSupport_status_idx" ON "Thread"("isSupport", "status");

-- AddForeignKey
ALTER TABLE "Thread" ADD CONSTRAINT "Thread_assignedAdminId_fkey" FOREIGN KEY ("assignedAdminId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
