import { propertyEmailDetails } from '../src/common/property-email';

describe('property details in booking emails', () => {
  const property = {
    title: 'Sunny <b>2-Bed</b> Flat',
    location: 'Lekki Phase 1',
    state: 'Lagos',
    category: 'APARTMENT',
    price: 1_200_000,
    priceUnit: 'YEAR',
    bedrooms: 2,
    bathrooms: 1,
    kitchens: 1,
    listingNumber: 42,
  };

  it('lists the name, listing number, address, type, rooms and price', () => {
    const { text } = propertyEmailDetails(property);
    expect(text).toContain('Property: Sunny <b>2-Bed</b> Flat (listing #42)');
    expect(text).toContain('Address: Lekki Phase 1, Lagos');
    expect(text).toContain('Type: Apartment');
    expect(text).toContain('Rooms: 2 bedrooms, 1 bathroom, 1 kitchen');
    expect(text).toContain('Price: ₦1,200,000 per year');
  });

  it('escapes the landlord-typed title in the HTML version', () => {
    const { html } = propertyEmailDetails(property);
    expect(html).toContain('Sunny &lt;b&gt;2-Bed&lt;/b&gt; Flat');
    expect(html).not.toContain('<b>2-Bed</b>');
  });
});
