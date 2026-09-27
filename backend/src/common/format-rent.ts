import { PriceUnit } from '@prisma/client';

/// "₦1,200,000/year": how rent is written in messages to tenants and
/// landlords (prices are stored in whole naira).
export function formatRent(naira: number, unit: PriceUnit): string {
  return `₦${naira.toLocaleString('en-US')}/${unit === PriceUnit.NIGHT ? 'night' : 'year'}`;
}
