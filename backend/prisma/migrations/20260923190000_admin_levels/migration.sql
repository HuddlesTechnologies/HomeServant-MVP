-- CreateEnum
CREATE TYPE "AdminLevel" AS ENUM ('SUPPORT', 'MODERATOR', 'SUPER_ADMIN');

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "adminLevel" "AdminLevel";

-- Backfill: any admin account created before this migration (via the
-- bootstrap endpoint, before tiers existed) becomes SUPER_ADMIN so it
-- isn't left with a null level that fails every AdminLevelGuard check.
UPDATE "User" SET "adminLevel" = 'SUPER_ADMIN' WHERE "role" = 'ADMIN';
