import { PrismaClient, UserRole } from '@prisma/client';
import { AdminService } from '../src/admin/admin.service';
import { fakePresence, makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb("admin view of a tenant's booking history (real Postgres)", () => {
  let prisma: PrismaClient;
  let admin: AdminService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });

  beforeEach(async () => {
    await resetDb(prisma);
    const log = { log: async () => undefined };
    admin = new AdminService(prisma as never, {} as never, {} as never, {} as never, {} as never, log as never, fakePresence(new Set()) as never, {} as never, {} as never);
  });

  let ref = 0;
  async function booking(tenantId: string, propertyId: string, landlordId: string, opts: {
    status: 'PAID_AWAITING_INSPECTION' | 'MOVED_IN' | 'REFUNDED' | 'DECLINED';
    createdAt: Date;
    payment?: Partial<{ status: 'PAID_HELD' | 'RELEASED' | 'REFUNDED' | 'FAILED'; refundRequestedBy: string; refundLastError: string; paidAt: Date; refundedAt: Date; releasedAt: Date; refundLastAttemptAt: Date }>;
  }) {
    const b = await prisma.booking.create({ data: { tenantId, propertyId, status: opts.status, createdAt: opts.createdAt } });
    if (opts.payment) {
      await prisma.payment.create({
        data: {
          purpose: 'RENTAL_BOOKING',
          bookingId: b.id,
          payerId: tenantId,
          recipientUserId: landlordId,
          amount: 100_000_000,
          platformFeeAmount: 5_000_000,
          paystackReference: `ref-${++ref}`,
          createdAt: opts.createdAt,
          ...opts.payment,
        },
      });
    }
    return b;
  }

  it('sends every booking newest first with its outcome, full property, images and a dated timeline', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const landlord = await makeUser(prisma, UserRole.LANDLORD, { fullName: 'Landlord Lara' });
    const property = await makeProperty(prisma, landlord.id);
    await prisma.property.update({
      where: { id: property.id },
      data: { imageUrl: 'https://img/cover.jpg', galleryUrls: ['https://img/cover.jpg', 'https://img/2.jpg'] },
    });

    const day = (d: number) => new Date(Date.UTC(2026, 0, d, 10));
    await booking(tenant.id, property.id, landlord.id, {
      status: 'MOVED_IN',
      createdAt: day(1),
      payment: { status: 'RELEASED', paidAt: day(1), releasedAt: day(5) },
    });
    await booking(tenant.id, property.id, landlord.id, {
      status: 'REFUNDED',
      createdAt: day(2),
      payment: { status: 'REFUNDED', paidAt: day(2), refundRequestedBy: 'TENANT', refundLastAttemptAt: day(3), refundedAt: day(3) },
    });
    await booking(tenant.id, property.id, landlord.id, {
      status: 'DECLINED',
      createdAt: day(3),
      payment: { status: 'REFUNDED', paidAt: day(3), refundRequestedBy: 'LANDLORD', refundLastAttemptAt: day(4), refundedAt: day(4) },
    });
    await booking(tenant.id, property.id, landlord.id, { status: 'PAID_AWAITING_INSPECTION', createdAt: day(4), payment: { status: 'FAILED' } });
    await booking(tenant.id, property.id, landlord.id, {
      status: 'PAID_AWAITING_INSPECTION',
      createdAt: day(5),
      payment: { status: 'PAID_HELD', paidAt: day(5), refundRequestedBy: 'TENANT', refundLastAttemptAt: day(6), refundLastError: 'Paystack is down' },
    });
    await booking(tenant.id, property.id, landlord.id, { status: 'PAID_AWAITING_INSPECTION', createdAt: day(6), payment: { status: 'PAID_HELD', paidAt: day(6) } });

    const detail = await admin.findUserDetail(tenant.id);
    expect(detail.bookings.map((b) => b.outcome)).toEqual([
      'Pending · paid, awaiting move-in',
      'Refund failed',
      'Payment failed',
      'Declined by landlord · refunded',
      'Refunded (tenant asked)',
      'Successful',
    ]);
    expect(detail.bookings.map((b) => b.outcomeTone)).toEqual(['pending', 'danger', 'danger', 'warning', 'warning', 'success']);

    const moved = detail.bookings[5];
    expect(moved.property).toMatchObject({ title: 'Test House', location: 'Lekki', bedrooms: 2, landlord: { fullName: 'Landlord Lara' } });
    expect(moved.property.images).toEqual(['https://img/cover.jpg', 'https://img/2.jpg']);
    expect(moved.timeline.map((e) => e.label)).toEqual(['Booking requested', 'Payment started', 'Payment successful', 'Paid out to the landlord']);
    expect(moved.timeline.every((e) => e.at instanceof Date)).toBe(true);

    const refunded = detail.bookings[4];
    expect(refunded.timeline.map((e) => e.label)).toEqual(expect.arrayContaining(['Refund requested', 'Refunded']));
    expect(refunded.timeline.find((e) => e.label === 'Refund requested')?.detail).toContain('the tenant asked for it');

    const failedRefund = detail.bookings[1];
    expect(failedRefund.timeline.find((e) => e.label === 'Refund failed')?.detail).toContain('Paystack is down');
  });
});
