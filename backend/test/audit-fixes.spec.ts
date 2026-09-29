import { NotFoundException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { AdminService } from '../src/admin/admin.service';
import { BookingsService } from '../src/bookings/bookings.service';
import { escapeHtml } from '../src/common/escape-html';
import { makeProperty, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

describe('escapeHtml', () => {
  it('neutralises markup in names, titles and reasons', () => {
    expect(escapeHtml(`<a href="x">Tolu</a> & 'co'`)).toBe('&lt;a href=&quot;x&quot;&gt;Tolu&lt;/a&gt; &amp; &#39;co&#39;');
  });
});

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('audit fixes (real Postgres)', () => {
  let prisma: PrismaClient;
  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
  });

  describe('GET /bookings/:id/tenancy-agreement', () => {
    async function movedInWithAgreement() {
      const tenant = await makeUser(prisma, UserRole.TENANT, { fullName: 'Tolu Bello' });
      const landlord = await makeUser(prisma, UserRole.LANDLORD, { fullName: 'Lara Adeyemi' });
      const property = await makeProperty(prisma, landlord.id, { isOccupied: true });
      const booking = await prisma.booking.create({ data: { tenantId: tenant.id, propertyId: property.id, status: 'MOVED_IN' } });
      await prisma.tenancyAgreement.create({
        data: {
          bookingId: booking.id,
          propertyTitle: property.title,
          propertyLocation: property.location,
          propertyState: property.state,
          rentAmount: property.price,
          priceUnit: property.priceUnit,
          leaseStartDate: new Date('2026-01-01'),
          leaseEndDate: new Date('2027-01-01'),
          landlordName: 'Lara Adeyemi',
          landlordEmail: landlord.email,
          tenantName: 'Tolu Bello',
          tenantEmail: tenant.email,
        },
      });
      return { tenant, landlord, booking };
    }
    const service = () => new BookingsService(prisma as never, {} as never, {} as never, {} as never, { postBookingSystemMessage: async () => null } as never);

    it("returns the agreement to the booking's tenant and landlord", async () => {
      const { tenant, landlord, booking } = await movedInWithAgreement();
      expect((await service().tenancyAgreement(booking.id, tenant.id)).tenantName).toBe('Tolu Bello');
      expect((await service().tenancyAgreement(booking.id, landlord.id)).landlordName).toBe('Lara Adeyemi');
    });

    it('is not found for anyone else, or before one exists', async () => {
      const { booking } = await movedInWithAgreement();
      const stranger = await makeUser(prisma, UserRole.TENANT);
      await expect(service().tenancyAgreement(booking.id, stranger.id)).rejects.toBeInstanceOf(NotFoundException);

      const tenant = await makeUser(prisma, UserRole.TENANT);
      const landlord = await makeUser(prisma, UserRole.LANDLORD);
      const property = await makeProperty(prisma, landlord.id);
      const pending = await prisma.booking.create({ data: { tenantId: tenant.id, propertyId: property.id, status: 'PAID_AWAITING_INSPECTION' } });
      await expect(service().tenancyAgreement(pending.id, tenant.id)).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  it("emails both the old and the new address when an admin changes a user's email, escaping the reason", async () => {
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
    const user = await makeUser(prisma, UserRole.TENANT);
    const sent: { to: string; html: string }[] = [];
    const mail = { send: async (to: string, _subject: string, html: string) => void sent.push({ to, html }) };
    const service = new (AdminService as unknown as new (...args: unknown[]) => AdminService)(
      prisma, null, mail, null, null, { log: async () => undefined }, null, null, null,
    );
    await service.updateUserEmail(user.id, { email: 'new.address@test.local', reason: 'Lost access <b>old</b> inbox' }, admin.id);

    expect(sent.map((m) => m.to).sort()).toEqual(['new.address@test.local', user.email].sort());
    for (const m of sent) {
      expect(m.html).toContain('Lost access &lt;b&gt;old&lt;/b&gt; inbox');
      expect(m.html).not.toContain('<b>old</b>');
    }
  });
});
