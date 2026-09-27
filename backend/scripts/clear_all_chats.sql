-- ==========================================================================
-- Clear ALL chat data (a one-off reset for testing). PERMANENT.
--
-- Deletes every conversation on the platform — tenant/landlord chats,
-- marketplace order chats and support chats — with their messages,
-- participants, transfer history and internal notes, plus the chat
-- notifications that pointed at them and the support dashboard's stats.
--
-- Does NOT touch: users, admins, properties, bookings, payments, orders,
-- reviews, reports, saved replies, push subscriptions, or non-chat
-- notifications (bookings, payments, vendor approvals, rent reminders...).
-- Photos sent in chats stay in Supabase Storage (folder "chat") — delete
-- that folder there too if you want them gone.
--
-- How to run (Supabase dashboard -> SQL Editor):
--   1. Take a backup first (Database -> Backups) if you might want it back.
--   2. Run PART 1 alone to see what will be deleted.
--   3. Run PART 2 alone. It runs in one transaction: all or nothing.
-- ==========================================================================

-- PART 1 — preview (changes nothing)
SELECT 'conversations' AS what, COUNT(*) FROM "Thread"
UNION ALL SELECT '  of which support', COUNT(*) FROM "Thread" WHERE "isSupport"
UNION ALL SELECT 'messages', COUNT(*) FROM "Message"
UNION ALL SELECT 'internal notes', COUNT(*) FROM "SupportNote"
UNION ALL SELECT 'transfer history rows', COUNT(*) FROM "ThreadTransferLog"
UNION ALL SELECT 'support dashboard rows', COUNT(*) FROM "SupportChatStat"
UNION ALL SELECT 'chat notifications', COUNT(*) FROM "Notification"
  WHERE "threadId" IS NOT NULL
     OR "type" IN ('NEW_MESSAGE', 'NEW_LISTING_MESSAGE', 'THREAD_TRANSFERRED', 'SUPPORT_THREAD_RESOLVED');

-- PART 2 — delete
BEGIN;
DELETE FROM "Notification"
  WHERE "threadId" IS NOT NULL
     OR "type" IN ('NEW_MESSAGE', 'NEW_LISTING_MESSAGE', 'THREAD_TRANSFERRED', 'SUPPORT_THREAD_RESOLVED');
DELETE FROM "SupportChatStat";
-- Removing the threads also removes their participants, messages,
-- transfer history and internal notes (ON DELETE CASCADE).
DELETE FROM "Thread";
COMMIT;
