-- Landlords' walkthrough videos are now saved with the listing (they were
-- picked in the app but never uploaded).
ALTER TABLE "Property" ADD COLUMN "videoUrl" TEXT;
