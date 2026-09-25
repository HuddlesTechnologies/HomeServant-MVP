import { Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { CreateShipmentInput, CreateShipmentResult, DeliveryProvider, ShipmentTrackingResult } from './delivery-provider.interface';

/// Development-only stand-in: logs the shipment request instead of
/// calling a real courier, and returns a fake shipment id/tracking
/// number so the rest of the fulfillment flow (storing shipmentId/
/// trackingNumber on the order item, the buyer's tracking screen) can be
/// exercised without a real GIG account. This is what
/// DELIVERY_PROVIDER=console (the default) wires up — mirrors
/// console-otp.provider.ts.
@Injectable()
export class ConsoleDeliveryProvider implements DeliveryProvider {
  private readonly logger = new Logger('Delivery');

  async createShipment(input: CreateShipmentInput): Promise<CreateShipmentResult> {
    const shipmentId = `dev-shipment-${randomUUID()}`;
    const trackingNumber = `DEV-${Math.floor(100000 + Math.random() * 900000)}`;
    this.logger.warn(
      `[DEV ONLY] Fake shipment created ${shipmentId} (tracking ${trackingNumber}): ` +
        `${input.itemDescription} from "${input.pickupAddress}" to "${input.dropoffAddress}"` +
        (input.weightKg ? ` (${input.weightKg}kg)` : ''),
    );
    return { shipmentId, trackingNumber, estimatedCost: undefined };
  }

  async trackShipment(shipmentId: string): Promise<ShipmentTrackingResult> {
    this.logger.warn(`[DEV ONLY] Fake tracking lookup for ${shipmentId}`);
    const now = new Date().toISOString();
    return {
      status: 'PENDING_PICKUP',
      lastUpdate: now,
      history: [{ status: 'PENDING_PICKUP', timestamp: now }],
    };
  }
}
