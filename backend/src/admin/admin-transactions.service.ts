import { Injectable } from '@nestjs/common';
import { PaymentPurpose, PaymentStatus, Prisma } from '@prisma/client';
import { joinName } from '../common/admin-display-name';
import { PrismaService } from '../prisma/prisma.service';

/// Which successful rent payments to list: every one the tenant's charge
/// went through for (the default), or only those credited to the landlord,
/// still held in escrow, or refunded to the tenant.
export type TransactionStatusFilter = 'credited' | 'held' | 'refunded';

const STATUS_FOR_FILTER: Record<TransactionStatusFilter, PaymentStatus> = {
  credited: PaymentStatus.RELEASED,
  held: PaymentStatus.PAID_HELD,
  refunded: PaymentStatus.REFUNDED,
};

/// A charge Paystack confirmed. INITIATED never went through and FAILED
/// never succeeded, so neither is a transaction.
const SUCCESSFUL_STATUSES: PaymentStatus[] = [PaymentStatus.PAID_HELD, PaymentStatus.RELEASED, PaymentStatus.REFUNDED];

const personSelect = {
  id: true,
  email: true,
  fullName: true,
  firstName: true,
  lastName: true,
  phoneNumber: true,
  profilePhotoUrl: true,
} as const;

const transactionInclude = {
  payer: { select: personSelect },
  recipient: { select: { ...personSelect, bankName: true, accountNumber: true, accountName: true } },
  booking: {
    select: {
      id: true,
      paymentPlan: true,
      nights: true,
      leaseStartDate: true,
      leaseEndDate: true,
      property: {
        select: {
          id: true,
          listingNumber: true,
          title: true,
          location: true,
          state: true,
          category: true,
          price: true,
          priceUnit: true,
          bedrooms: true,
          bathrooms: true,
          imageUrl: true,
          galleryUrls: true,
        },
      },
    },
  },
} satisfies Prisma.PaymentInclude;

type TransactionRow = Prisma.PaymentGetPayload<{ include: typeof transactionInclude }>;

function person(user: TransactionRow['payer']) {
  return {
    id: user.id,
    name: joinName(user.firstName, user.lastName, user.fullName) || user.email,
    email: user.email,
    phoneNumber: user.phoneNumber,
    profilePhotoUrl: user.profilePhotoUrl,
  };
}

/// Every successful rent payment — who paid, which landlord it was for,
/// when the tenant paid and when the landlord was credited, the property
/// and the Paystack references — for the admin console's Transactions page.
/// Read-only and open to every admin tier (support staff answer "did my
/// payment go through?" questions all day), so the landlord's account
/// number is only ever sent as its last four digits.
@Injectable()
export class AdminTransactionsService {
  constructor(private readonly prisma: PrismaService) {}

  async findTransactions(page = 1, pageSize = 20, search?: string, status?: TransactionStatusFilter) {
    page = Number.isFinite(page) && page > 0 ? Math.floor(page) : 1;
    pageSize = Number.isFinite(pageSize) && pageSize > 0 ? Math.min(Math.floor(pageSize), 100) : 20;
    const where = AdminTransactionsService.where(search, status);
    const [items, total] = await Promise.all([
      this.prisma.payment.findMany({
        where,
        include: transactionInclude,
        orderBy: [{ paidAt: 'desc' }, { createdAt: 'desc' }],
        skip: (page - 1) * pageSize,
        take: pageSize,
      }),
      this.prisma.payment.count({ where }),
    ]);
    return { items: items.map(AdminTransactionsService.toTransaction), total, page, pageSize };
  }

  /// Search matches, case-insensitively and anywhere in the text: the
  /// Paystack payment or payout reference, the tenant's or landlord's name,
  /// email or phone number, and the property's title or location. A purely
  /// numeric search also matches the listing number exactly.
  static where(search?: string, status?: TransactionStatusFilter): Prisma.PaymentWhereInput {
    const term = search?.trim();
    const statusFilter = status && STATUS_FOR_FILTER[status] ? STATUS_FOR_FILTER[status] : undefined;
    const where: Prisma.PaymentWhereInput = {
      purpose: PaymentPurpose.RENTAL_BOOKING,
      status: statusFilter ?? { in: SUCCESSFUL_STATUSES },
    };
    if (!term) return where;
    const contains = { contains: term, mode: 'insensitive' as const };
    const personMatch: Prisma.UserWhereInput = {
      OR: [{ fullName: contains }, { firstName: contains }, { lastName: contains }, { email: contains }, { phoneNumber: contains }],
    };
    const propertyMatch: Prisma.PropertyWhereInput[] = [{ title: contains }, { location: contains }];
    if (/^\d+$/.test(term)) propertyMatch.push({ listingNumber: Number(term) });
    return {
      ...where,
      OR: [
        { paystackReference: contains },
        { payoutReference: contains },
        { payer: personMatch },
        { recipient: personMatch },
        { booking: { property: { OR: propertyMatch } } },
      ],
    };
  }

  static toTransaction(row: TransactionRow) {
    const property = row.booking?.property ?? null;
    const landlordShareKobo = row.amount - row.platformFeeAmount;
    return {
      id: row.id,
      status: row.status,
      amountKobo: row.amount,
      platformFeeKobo: row.platformFeeAmount,
      landlordShareKobo,
      reference: row.paystackReference,
      payoutReference: row.payoutReference,
      paidAt: row.paidAt ?? row.createdAt,
      creditedAt: row.releasedAt,
      refundedAt: row.refundedAt,
      refundReason: row.refundReason,
      heldForVerification: row.heldForVerificationAt != null,
      tenant: person(row.payer),
      landlord: {
        ...person(row.recipient),
        bankName: row.recipient.bankName,
        accountName: row.recipient.accountName,
        accountLast4: row.recipient.accountNumber ? row.recipient.accountNumber.slice(-4) : null,
      },
      booking: row.booking
        ? {
            id: row.booking.id,
            paymentPlan: row.booking.paymentPlan,
            nights: row.booking.nights,
            leaseStartDate: row.booking.leaseStartDate,
            leaseEndDate: row.booking.leaseEndDate,
          }
        : null,
      property,
    };
  }
}
