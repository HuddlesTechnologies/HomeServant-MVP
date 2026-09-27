-- Emails are stored lower-cased and trimmed (the API normalises every
-- email it receives — see NormalizeEmail). These rules make the database
-- enforce it too, so two accounts differing only by case (Ada@x.com vs
-- ada@x.com) can't exist even through a direct database edit: with the
-- existing unique index on email, a lower-case-only column can't hold
-- case variants of one address.
--
-- Prerequisite (already true — see 20260928140000_lowercase_emails):
--   SELECT count(*) FROM "User" WHERE email <> lower(trim(email));  -- 0
ALTER TABLE "User" ADD CONSTRAINT "User_email_lowercase" CHECK ("email" = lower(trim("email")));
ALTER TABLE "PendingAdmin" ADD CONSTRAINT "PendingAdmin_email_lowercase" CHECK ("email" = lower(trim("email")));
