-- One Paystack checkout per marketplace order, and unpaid orders expiring.
ALTER TABLE "MarketplaceOrder" ADD COLUMN "paystackReference" TEXT;
ALTER TABLE "MarketplaceOrder" ADD COLUMN "authorizationUrl" TEXT;
ALTER TABLE "MarketplaceOrder" ADD COLUMN "paymentExpiresAt" TIMESTAMP(3);
ALTER TABLE "MarketplaceOrder" ADD COLUMN "refundLockedAt" TIMESTAMP(3);
CREATE UNIQUE INDEX "MarketplaceOrder_paystackReference_key" ON "MarketplaceOrder"("paystackReference");

ALTER TABLE "Payment" ADD COLUMN "chargeReference" TEXT;
CREATE INDEX "Payment_chargeReference_idx" ON "Payment"("chargeReference");
