-- Monthly rent: landlords can allow it per listing; tenants pay the first
-- month up front and then month by month.
CREATE TYPE "PaymentPlan" AS ENUM ('FULL', 'MONTHLY');

ALTER TABLE "Property" ADD COLUMN "allowMonthlyPayment" BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE "Booking" ADD COLUMN "paymentPlan" "PaymentPlan" NOT NULL DEFAULT 'FULL',
ADD COLUMN "monthlyRent" INTEGER,
ADD COLUMN "rentPaidThrough" TIMESTAMP(3),
ADD COLUMN "monthlyReminderSentFor" TIMESTAMP(3),
ADD COLUMN "monthlyOverdueNotifiedFor" TIMESTAMP(3);
