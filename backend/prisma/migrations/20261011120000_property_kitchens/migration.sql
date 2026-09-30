-- How many kitchens a listing has (existing listings assume one).
ALTER TABLE "Property" ADD COLUMN "kitchens" INTEGER NOT NULL DEFAULT 1;
