-- Customers can end their own support conversation.
-- AlterTable
ALTER TABLE "SupportChatStat" ADD COLUMN     "closedByCustomer" BOOLEAN NOT NULL DEFAULT false;

