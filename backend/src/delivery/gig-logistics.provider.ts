import { Injectable, Logger } from '@nestjs/common';
import { CreateShipmentInput, CreateShipmentResult, DeliveryProvider, ShipmentTrackingResult } from './delivery-provider.interface';

/// Best-effort real implementation for GIG Logistics.
///
/// UNVERIFIED — read before touching production traffic: GIG has no
/// public technical API documentation (their developer page is a
/// contact-sales landing page with zero endpoint/auth details), and
/// there is no GIG account/API key to test against yet. Everything
/// below — the endpoint paths, the request/response field names, even
/// the Bearer-token auth scheme itself — is a guess based on generic
/// REST/logistics-API conventions, not a confirmed contract. Treat this
/// as a starting point to correct once real GIG docs and credentials
/// are available, not as a working integration.
///
/// Configured via GIG_API_KEY (sent as a Bearer token) and
/// GIG_API_BASE_URL (e.g. "https://api.giglogistics.com/v1" — the real
/// base URL is also unconfirmed) so nothing here is hardcoded.
@Injectable()
export class GigLogisticsProvider implements DeliveryProvider {
  private readonly logger = new Logger('Delivery');

  constructor(
    private readonly apiKey: string,
    private readonly baseUrl: string,
  ) {}

  private get headers() {
    return {
      Authorization: `Bearer ${this.apiKey}`,
      'Content-Type': 'application/json',
    };
  }

  async createShipment(input: CreateShipmentInput): Promise<CreateShipmentResult> {
    // Guessed endpoint/payload shape — unverified against a real GIG
    // contract. Adjust field names once real docs exist.
    const response = await fetch(`${this.baseUrl}/shipments`, {
      method: 'POST',
      headers: this.headers,
      body: JSON.stringify({
        pickup_address: input.pickupAddress,
        dropoff_address: input.dropoffAddress,
        item_description: input.itemDescription,
        weight_kg: input.weightKg,
      }),
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      this.logger.error(`GIG createShipment failed (${response.status}): ${body}`);
      throw new Error('Failed to create shipment with GIG Logistics');
    }

    // Guessed response shape — unverified.
    const data = (await response.json()) as {
      shipment_id?: string;
      id?: string;
      tracking_number?: string;
      tracking_code?: string;
      estimated_cost?: number;
    };

    const shipmentId = data.shipment_id ?? data.id;
    const trackingNumber = data.tracking_number ?? data.tracking_code;
    if (!shipmentId || !trackingNumber) {
      throw new Error('Unexpected response shape from GIG Logistics (createShipment)');
    }

    return {
      shipmentId,
      trackingNumber,
      estimatedCost: data.estimated_cost,
    };
  }

  async trackShipment(shipmentId: string): Promise<ShipmentTrackingResult> {
    // Guessed endpoint/payload shape — unverified against a real GIG
    // contract. Adjust field names once real docs exist.
    const response = await fetch(`${this.baseUrl}/shipments/${encodeURIComponent(shipmentId)}/tracking`, {
      method: 'GET',
      headers: this.headers,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      this.logger.error(`GIG trackShipment failed (${response.status}): ${body}`);
      throw new Error('Failed to fetch shipment tracking from GIG Logistics');
    }

    // Guessed response shape — unverified.
    const data = (await response.json()) as {
      status?: string;
      last_update?: string;
      history?: Array<{ status?: string; timestamp?: string; location?: string }>;
    };

    return {
      status: data.status ?? 'UNKNOWN',
      lastUpdate: data.last_update ?? new Date().toISOString(),
      history: (data.history ?? []).map((h) => ({
        status: h.status ?? 'UNKNOWN',
        timestamp: h.timestamp ?? new Date().toISOString(),
        location: h.location,
      })),
    };
  }
}
