-- AlterTable
ALTER TABLE "User" ADD COLUMN "profileCompletedAt" TIMESTAMP(3);

-- Backfill: every account that already exists has been through signup, so
-- it must never be sent back into the profile-completion wizard. Only
-- tenant/landlord accounts that never even got past the name/phone step
-- (abandoned right after OTP verification, or a first-time Google sign-in
-- that never added a phone number) are left unset.
UPDATE "User"
SET "profileCompletedAt" = NOW()
WHERE "role" NOT IN ('TENANT', 'LANDLORD')
   OR (COALESCE(BTRIM("fullName"), '') <> '' AND COALESCE(BTRIM("phoneNumber"), '') <> '');
