import { escapeHtml } from './escape-html';

/// What a booking email shows about the property.
export interface EmailProperty {
  title: string;
  location: string;
  state: string;
  category: string;
  price: number;
  priceUnit: string;
  bedrooms: number;
  bathrooms: number;
  kitchens: number;
  listingNumber: number;
}

const CATEGORY: Record<string, string> = { HOUSE: 'House', APARTMENT: 'Apartment', SHORTLET: 'Shortlet', SELF_CON: 'Self-con' };
const UNIT: Record<string, string> = { YEAR: 'year', MONTH: 'month', NIGHT: 'night', WEEK: 'week' };

/// The property details block added under every booking, payment, rent and
/// tenancy email, so the recipient can tell which listing it's about
/// without opening the app. Returns the HTML and plain-text versions.
export function propertyEmailDetails(p: EmailProperty): { html: string; text: string } {
  const rows: [string, string][] = [
    ['Property', `${p.title} (listing #${p.listingNumber})`],
    ['Address', `${p.location}, ${p.state}`],
    ['Type', CATEGORY[p.category] ?? p.category],
    ['Rooms', `${p.bedrooms} bedroom${p.bedrooms === 1 ? '' : 's'}, ${p.bathrooms} bathroom${p.bathrooms === 1 ? '' : 's'}, ${p.kitchens} kitchen${p.kitchens === 1 ? '' : 's'}`],
    ['Price', `₦${p.price.toLocaleString('en-NG')} per ${UNIT[p.priceUnit] ?? p.priceUnit.toLowerCase()}`],
  ];
  const html =
    '<table style="margin-top:16px;border-collapse:collapse;font-size:14px;color:#132442">' +
    rows
      .map(([k, v]) => `<tr><td style="padding:4px 12px 4px 0;color:#5B6170">${k}</td><td style="padding:4px 0"><strong>${escapeHtml(v)}</strong></td></tr>`)
      .join('') +
    '</table>';
  const text = '\n\n' + rows.map(([k, v]) => `${k}: ${v}`).join('\n');
  return { html, text };
}

/// The Prisma `select` for the fields [propertyEmailDetails] needs.
export const EMAIL_PROPERTY_SELECT = {
  title: true,
  location: true,
  state: true,
  category: true,
  price: true,
  priceUnit: true,
  bedrooms: true,
  bathrooms: true,
  kitchens: true,
  listingNumber: true,
} as const;
