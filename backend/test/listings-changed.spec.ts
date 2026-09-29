import { Prisma } from '@prisma/client';
import { changesListings } from '../src/prisma/prisma.service';

const params = (model: string, action: string, args: unknown = {}) =>
  ({ model, action, args, dataPath: [], runInTransaction: false }) as unknown as Prisma.MiddlewareParams;

describe('which writes tell apps that listings changed', () => {
  it('any listing write', () => {
    expect(changesListings(params('Property', 'update', { data: { price: 1 } }))).toBe(true);
    expect(changesListings(params('Property', 'create'))).toBe(true);
    expect(changesListings(params('Property', 'delete'))).toBe(true);
    expect(changesListings(params('Property', 'findMany'))).toBe(false);
  });

  it('a booking changing status, but not other booking edits', () => {
    expect(changesListings(params('Booking', 'update', { data: { status: 'PAID_AWAITING_INSPECTION' } }))).toBe(true);
    expect(changesListings(params('Booking', 'updateMany', { data: { status: 'REFUNDED' } }))).toBe(true);
    expect(changesListings(params('Booking', 'update', { data: { message: 'hi' } }))).toBe(false);
    expect(changesListings(params('Booking', 'create', { data: { status: 'PENDING' } }))).toBe(false);
  });

  it('nothing else', () => {
    expect(changesListings(params('Message', 'create'))).toBe(false);
  });
});
