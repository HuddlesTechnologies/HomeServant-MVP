import { changesListings } from '../src/prisma/prisma.service';

describe('which writes tell apps that listings changed', () => {
  it('any listing write', () => {
    expect(changesListings('Property', 'update', { data: { price: 1 } })).toBe(true);
    expect(changesListings('Property', 'create', {})).toBe(true);
    expect(changesListings('Property', 'delete', {})).toBe(true);
    expect(changesListings('Property', 'findMany', {})).toBe(false);
  });

  it('a booking changing status, but not other booking edits', () => {
    expect(changesListings('Booking', 'update', { data: { status: 'PAID_AWAITING_INSPECTION' } })).toBe(true);
    expect(changesListings('Booking', 'updateMany', { data: { status: 'REFUNDED' } })).toBe(true);
    expect(changesListings('Booking', 'update', { data: { message: 'hi' } })).toBe(false);
    expect(changesListings('Booking', 'create', { data: { status: 'PENDING' } })).toBe(false);
  });

  it('nothing else', () => {
    expect(changesListings('Message', 'create', {})).toBe(false);
    expect(changesListings(undefined, '$queryRaw', {})).toBe(false);
  });
});
