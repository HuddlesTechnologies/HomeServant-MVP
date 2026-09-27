-- Who first took up a support conversation, and who performed each hand-off.
CREATE TYPE "ThreadHandoffKind" AS ENUM ('CLAIM', 'TRANSFER', 'REASSIGN');
ALTER TABLE "ThreadTransferLog" ADD COLUMN "kind" "ThreadHandoffKind" NOT NULL DEFAULT 'TRANSFER';
ALTER TABLE "ThreadTransferLog" ADD COLUMN "actorId" TEXT;
