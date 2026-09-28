-- Tenant booking profile: a short background and hobbies landlords read
-- with a booking request.
ALTER TABLE "User" ADD COLUMN "bio" TEXT,
ADD COLUMN "hobbies" TEXT[] DEFAULT ARRAY[]::TEXT[];
