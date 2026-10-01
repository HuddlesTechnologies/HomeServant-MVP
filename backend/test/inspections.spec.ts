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

  it('landlord can replace a proposed date, and move a confirmed one (it stays confirmed)', async () => {
    const { tenant, landlord, booking } = await paidBooking();
    await bookings.proposeInspection(booking.id, tenant.id, { requestedDate: inDays(3) });
    await bookings.scheduleInspection(booking.id, landlord.id, { requestedDate: inDays(6) });
    const newDate = inDays(7);
    const moved = await bookings.scheduleInspection(booking.id, landlord.id, { requestedDate: newDate });
    expect(moved.status).toBe('INSPECTION_CONFIRMED');
    expect(moved.requestedDate!.toISOString()).toBe(newDate);
    expect(chatNotes[2]).toMatch(/^The landlord moved the inspection of Test House from .+ to /);
  });

  it('tenant can ask to move a confirmed date; it goes back to the landlord to accept', async () => {
    const { tenant, landlord, booking } = await paidBooking();
    await bookings.scheduleInspection(booking.id, landlord.id, { requestedDate: inDays(4) });
    const asked = await bookings.proposeInspection(booking.id, tenant.id, { requestedDate: inDays(8) });
    expect(asked.status).toBe('INSPECTION_PROPOSED');
    expect(asked.inspectionConfirmedAt).toBeNull();
    expect(chatNotes[1]).toMatch(/^The tenant asked to move the inspection of Test House from .+ to .+ The landlord can confirm it/);
    expect((await bookings.respondToInspection(booking.id, landlord.id, true)).status).toBe('INSPECTION_CONFIRMED');
  });

  it('once the tenant has moved in, the date can no longer be changed', async () => {
    const { tenant, landlord, booking } = await paidBooking();
    await prisma.booking.update({ where: { id: booking.id }, data: { status: 'MOVED_IN' } });
    await expect(bookings.proposeInspection(booking.id, tenant.id, { requestedDate: inDays(3) })).rejects.toBeInstanceOf(BadRequestException);
    await expect(bookings.scheduleInspection(booking.id, landlord.id, { requestedDate: inDays(3) })).rejects.toBeInstanceOf(BadRequestException);
  });

  it('refuses a date in the past', async () => {
    const { tenant, booking } = await paidBooking();
    await expect(bookings.proposeInspection(booking.id, tenant.id, { requestedDate: inDays(-5) })).rejects.toBeInstanceOf(BadRequestException);
  });
});
