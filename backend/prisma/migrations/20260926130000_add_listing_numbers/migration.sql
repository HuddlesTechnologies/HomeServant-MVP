-- AlterTable: give every existing Property a sequential listingNumber,
-- assigned in createdAt order (oldest listing = 1), then wire up a
-- sequence-backed default + uniqueness for every future row.
CREATE SEQUENCE IF NOT EXISTS "Property_listingNumber_seq";
ALTER TABLE "Property" ADD COLUMN "listingNumber" INTEGER;

WITH numbered AS (
  SELECT "id", ROW_NUMBER() OVER (ORDER BY "createdAt") AS rn
  FROM "Property"
)
UPDATE "Property" p
SET "listingNumber" = numbered.rn
FROM numbered
WHERE p."id" = numbered."id";

ALTER TABLE "Property" ALTER COLUMN "listingNumber" SET NOT NULL;
ALTER TABLE "Property" ALTER COLUMN "listingNumber" SET DEFAULT nextval('"Property_listingNumber_seq"');
ALTER SEQUENCE "Property_listingNumber_seq" OWNED BY "Property"."listingNumber";
SELECT setval('"Property_listingNumber_seq"', COALESCE((SELECT MAX("listingNumber") FROM "Property"), 0) + 1, false);
CREATE UNIQUE INDEX "Property_listingNumber_key" ON "Property"("listingNumber");

-- AlterTable: same treatment for Product, on its own independent sequence.
CREATE SEQUENCE IF NOT EXISTS "Product_listingNumber_seq";
ALTER TABLE "Product" ADD COLUMN "listingNumber" INTEGER;

WITH numbered AS (
  SELECT "id", ROW_NUMBER() OVER (ORDER BY "createdAt") AS rn
  FROM "Product"
)
UPDATE "Product" p
SET "listingNumber" = numbered.rn
FROM numbered
WHERE p."id" = numbered."id";

ALTER TABLE "Product" ALTER COLUMN "listingNumber" SET NOT NULL;
ALTER TABLE "Product" ALTER COLUMN "listingNumber" SET DEFAULT nextval('"Product_listingNumber_seq"');
ALTER SEQUENCE "Product_listingNumber_seq" OWNED BY "Product"."listingNumber";
SELECT setval('"Product_listingNumber_seq"', COALESCE((SELECT MAX("listingNumber") FROM "Product"), 0) + 1, false);
CREATE UNIQUE INDEX "Product_listingNumber_key" ON "Product"("listingNumber");
