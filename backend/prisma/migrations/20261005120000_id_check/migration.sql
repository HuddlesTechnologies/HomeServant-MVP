-- CreateEnum
CREATE TYPE "IdCheckStatus" AS ENUM ('NOT_RUN', 'MATCH', 'MISMATCH', 'NOT_FOUND', 'UNSUPPORTED', 'ERROR');

-- AlterTable
ALTER TABLE "IdentityVerification"
    ADD COLUMN "idCheckStatus" "IdCheckStatus" NOT NULL DEFAULT 'NOT_RUN',
    ADD COLUMN "idCheckProvider" TEXT,
    ADD COLUMN "idCheckReference" TEXT,
    ADD COLUMN "idCheckName" TEXT,
    ADD COLUMN "idCheckDetail" TEXT,
    ADD COLUMN "idCheckedAt" TIMESTAMP(3),
    ADD COLUMN "autoApproved" BOOLEAN NOT NULL DEFAULT false;
