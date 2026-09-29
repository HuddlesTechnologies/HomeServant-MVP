import { BadRequestException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { BookingsService } from '../src/bookings/bookings.service';
import { makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;
const inDays = (n: number) => new Date(Date.now() + n * 86_400_000).toISOString();

describeDb('inspection dates (real Postgres)', () => {
  let prisma: PrismaClient;
  let chatNotes: string[];
  let bookings: BookingsService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    chatNotes = [];
    const chat = { postBookingSystemMessage: async (o: { body: string }) => void chatNotes.push(o.body) };
    const notifications = { create: async () => undefined };
    bookings = new BookingsService(prisma as never, notifications as never, {} as never, {} as never, chat as never);
  });

  async function paidBooking() {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const property = await makeProperty(prisma, landlord.id);
    const booking = await prisma.booking.create({ data: { tenantId: tenant.id, propertyId: property.id, status: 'PAID_AWAITING_INSPECTION' } });
    return { tenant, landlord, booking };
  }

  it('tenant proposes, can change the date, landlord confirms; each step is noted in their chat', async () => {
    const { tenant, landlord, booking } = await paidBooking();
    await bookings.proposeInspection(booking.id, tenant.id, { requestedDate: inDays(3) });
    // Changing a date that's still waiting on the landlord used to fail.
    await bookings.proposeInspection(booking.id, tenant.id, { requestedDate: inDays(5) });
    const confirmed = await bookings.respondToInspection(booking.id, landlord.id, true);

    expect(confirmed.status).toBe('INSPECTION_CONFIRMED');
    expect(chatNotes).toHaveLength(3);
    expect(chatNotes[0]).toMatch(/^Inspection date proposed for Test House/);
    expect(chatNotes[2]).toMatch(/^The landlord confirmed the inspection of Test House on /);
  });

  it('landlord sets the date when the tenant never proposed one', async () => {
    const { landlord, booking } = await paidBooking();
    const set = await bookings.scheduleInspection(booking.id, landlord.id, { requestedDate: inDays(4) });
    expect(set.status).toBe('INSPECTION_CONFIRMED');
    expect(set.requestedDate).not.toBeNull();
    expect(chatNotes[0]).toMatch(/^The landlord set the inspection of Test House for /);
  });

  it('landlord can replace a proposed date, but not once the inspection is confirmed', async () => {
    const { tenant, landlord, booking } = await paidBooking();
    await bookings.proposeInspection(booking.id, tenant.id, { requestedDate: inDays(3) });
    await bookings.scheduleInspection(booking.id, landlord.id, { requestedDate: inDays(6) });
    await expect(bookings.scheduleInspection(booking.id, landlord.id, { requestedDate: inDays(7) })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('refuses a date in the past', async () => {
    const { tenant, booking } = await paidBooking();
    await expect(bookings.proposeInspection(booking.id, tenant.id, { requestedDate: inDays(-5) })).rejects.toBeInstanceOf(BadRequestException);
  });
});
