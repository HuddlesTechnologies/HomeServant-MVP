-- Who created each admin account (console invite flow).
-- AlterTable
ALTER TABLE "PendingAdmin" ADD COLUMN     "invitedById" TEXT;

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "createdByAdminId" TEXT;

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_createdByAdminId_fkey" FOREIGN KEY ("createdByAdminId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;

