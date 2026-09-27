-- Support dashboard stats (with customer ratings) and unclaimed-chat escalation.
-- AlterTable
ALTER TABLE "Thread" ADD COLUMN     "unclaimedEscalatedAt" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "SupportChatStat" (
    "id" TEXT NOT NULL,
    "threadId" TEXT NOT NULL,
    "customerId" TEXT,
    "customerRole" "UserRole",
    "topic" "SupportTopic",
    "priority" "SupportPriority" NOT NULL DEFAULT 'NORMAL',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "firstCustomerMessageAt" TIMESTAMP(3),
    "firstResponseAt" TIMESTAMP(3),
    "firstResponderId" TEXT,
    "currentAdminId" TEXT,
    "transferCount" INTEGER NOT NULL DEFAULT 0,
    "resolvedAt" TIMESTAMP(3),
    "resolvedById" TEXT,
    "rating" INTEGER,
    "ratingComment" TEXT,
    "ratedAt" TIMESTAMP(3),

    CONSTRAINT "SupportChatStat_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SupportChatStat_threadId_key" ON "SupportChatStat"("threadId");

-- CreateIndex
CREATE INDEX "SupportChatStat_createdAt_idx" ON "SupportChatStat"("createdAt");

-- CreateIndex
CREATE INDEX "SupportChatStat_resolvedAt_idx" ON "SupportChatStat"("resolvedAt");


-- Backfill: one stats row per existing support conversation. Who resolved
-- a conversation wasn't recorded before, so resolvedById stays empty.
INSERT INTO "SupportChatStat" (
  "id", "threadId", "customerId", "customerRole", "topic", "priority", "createdAt",
  "firstCustomerMessageAt", "firstResponseAt", "firstResponderId", "currentAdminId",
  "transferCount", "resolvedAt"
)
SELECT
  gen_random_uuid()::text,
  t."id",
  c."id",
  c."role",
  t."supportTopic",
  t."priority",
  t."createdAt",
  (SELECT MIN(m."createdAt") FROM "Message" m JOIN "User" u ON u."id" = m."senderId"
     WHERE m."threadId" = t."id" AND u."role" <> 'ADMIN'),
  fr."createdAt",
  fr."senderId",
  t."assignedAdminId",
  (SELECT COUNT(*)::int FROM "ThreadTransferLog" l
     WHERE l."threadId" = t."id" AND l."kind" IN ('TRANSFER', 'REASSIGN')),
  t."resolvedAt"
FROM "Thread" t
LEFT JOIN LATERAL (
  SELECT u."id", u."role" FROM "ThreadParticipant" p JOIN "User" u ON u."id" = p."userId"
  WHERE p."threadId" = t."id" AND u."role" <> 'ADMIN' LIMIT 1
) c ON TRUE
LEFT JOIN LATERAL (
  SELECT m."createdAt", m."senderId" FROM "Message" m JOIN "User" u ON u."id" = m."senderId"
  WHERE m."threadId" = t."id" AND u."role" = 'ADMIN' ORDER BY m."createdAt" ASC LIMIT 1
) fr ON TRUE
WHERE t."isSupport" = TRUE
ON CONFLICT ("threadId") DO NOTHING;
