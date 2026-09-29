import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AdminLevel, PaymentStatus } from '@prisma/client';
import { AdminLevelGuard } from '../src/common/guards/admin-level.guard';
import { AdminTransactionsController } from '../src/admin/admin-transactions.controller';
import { AdminTransactionsService } from '../src/admin/admin-transactions.service';

describe('Admin Transactions page', () => {
  it.each(['SUPPORT', 'MODERATOR', 'SUPER_ADMIN'] as AdminLevel[])('is open to %s admins', (adminLevel) => {
    const context = {
      getHandler: () => AdminTransactionsController.prototype.list,
      getClass: () => AdminTransactionsController,
      switchToHttp: () => ({ getRequest: () => ({ user: { adminLevel } }) }),
    } as unknown as ExecutionContext;
    expect(new AdminLevelGuard(new Reflector()).canActivate(context)).toBe(true);
  });

  it('lists only successful rent payments by default', () => {
    expect(AdminTransactionsService.where()).toEqual({
      purpose: 'RENTAL_BOOKING',
      status: { in: [PaymentStatus.PAID_HELD, PaymentStatus.RELEASED, PaymentStatus.REFUNDED] },
    });
    expect(AdminTransactionsService.where('  ', 'credited')).toEqual({ purpose: 'RENTAL_BOOKING', status: PaymentStatus.RELEASED });
  });

  it('searches references, tenant, landlord and property, and a listing number exactly', () => {
    const where = AdminTransactionsService.where('42');
    const or = where.OR as Record<string, unknown>[];
    expect(or.map((clause) => Object.keys(clause)[0])).toEqual(['paystackReference', 'payoutReference', 'payer', 'recipient', 'booking']);
    expect(JSON.stringify(or[4])).toContain('"listingNumber":42');
    expect(JSON.stringify(AdminTransactionsService.where('Lekki'))).not.toContain('listingNumber');
  });

  it('never sends the full account number and works out the landlord share', () => {
    const person = { id: 'u', email: 'a@b.c', fullName: 'Ada Obi', firstName: null, lastName: null, phoneNumber: null, profilePhotoUrl: null };
    const paidAt = new Date('2026-09-01T10:00:00Z');
    const row = {
      id: 'p1',
      status: PaymentStatus.RELEASED,
      amount: 100000,
      platformFeeAmount: 5000,
      paystackReference: 'ref_1',
      payoutReference: 'po_1',
      paidAt,
      releasedAt: paidAt,
      refundedAt: null,
      refundReason: null,
      heldForVerificationAt: null,
      createdAt: paidAt,
      payer: person,
      recipient: { ...person, id: 'l', bankName: 'GTBank', accountNumber: '0123456789', accountName: 'ADA OBI' },
      booking: null,
    } as unknown as Parameters<typeof AdminTransactionsService.toTransaction>[0];
    const t = AdminTransactionsService.toTransaction(row);
    expect(t.landlordShareKobo).toBe(95000);
    expect(t.landlord.accountLast4).toBe('6789');
    expect(JSON.stringify(t)).not.toContain('0123456789');
  });
});
