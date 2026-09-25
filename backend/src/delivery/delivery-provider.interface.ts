/// A pluggable delivery/logistics channel — mirrors the OtpProvider
/// pattern (see otp-provider.interface.ts): MarketplaceOrdersService
/// depends only on this interface, so swapping the real courier later is
/// a one-file change plus an env var, not a rewrite of the fulfillment
/// flow.
///
/// IMPORTANT — unverified shape: GIG Logistics has no public technical
/// API documentation (their developer page is a contact-sales landing
/// page with zero endpoint/auth details), and there is no GIG account or
/// credentials to test against yet. The method signatures and return
/// shapes below are a best-effort guess based on common
/// courier/logistics API conventions (Sendy, Shipbubble, Bento, etc.),
/// NOT a real contract. Once a real GIG account and API docs exist,
/// revisit this interface (and GigLogisticsProvider) and correct
/// whatever doesn't match reality.
export interface CreateShipmentInput {
  pickupAddress: string;
  dropoffAddress: string;
  itemDescription: string;
  weightKg?: number;
}

export interface CreateShipmentResult {
  shipmentId: string;
  trackingNumber: string;
  estimatedCost?: number;
}

export interface ShipmentTrackingEvent {
  status: string;
  timestamp: string;
  location?: string;
}

export interface ShipmentTrackingResult {
  status: string;
  lastUpdate: string;
  history: ShipmentTrackingEvent[];
}

export interface DeliveryProvider {
  /// Books a shipment for one marketplace order item. Should throw if the
  /// courier rejects/fails the request, so the caller can surface an
  /// error instead of silently recording a shipment that was never
  /// actually created.
  createShipment(input: CreateShipmentInput): Promise<CreateShipmentResult>;

  /// Looks up the current status/history of a previously created
  /// shipment by the id [createShipment] returned.
  trackShipment(shipmentId: string): Promise<ShipmentTrackingResult>;
}
