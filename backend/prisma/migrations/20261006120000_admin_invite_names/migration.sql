-- Admin invites now collect first and last name separately (customers are
-- only ever shown an admin's first name).
ALTER TABLE "PendingAdmin" ADD COLUMN "firstName" TEXT,
ADD COLUMN "lastName" TEXT;
