-- Emails are now compared without regard to case: the API lower-cases and
-- trims every email it receives (NormalizeEmail). Bring existing rows in
-- line so "Ada@Example.com" can still sign in as "ada@example.com".
--
-- A row is only changed when no OTHER row would end up with the same
-- address; any such clash (two accounts differing only by case) is left
-- untouched, so this can never fail on the unique index. Find leftovers with:
--   SELECT lower(email), array_agg(email) FROM "User"
--   GROUP BY lower(email) HAVING count(*) > 1;

UPDATE "User" u
SET "email" = lower(trim(u."email"))
WHERE u."email" <> lower(trim(u."email"))
  AND NOT EXISTS (
    SELECT 1 FROM "User" o
    WHERE o."id" <> u."id" AND lower(trim(o."email")) = lower(trim(u."email"))
  );

UPDATE "PendingAdmin" p
SET "email" = lower(trim(p."email"))
WHERE p."email" <> lower(trim(p."email"))
  AND NOT EXISTS (
    SELECT 1 FROM "PendingAdmin" o
    WHERE o."id" <> p."id" AND lower(trim(o."email")) = lower(trim(p."email"))
  );

UPDATE "OtpCode" SET "destination" = lower(trim("destination"))
WHERE "destination" <> lower(trim("destination"));
