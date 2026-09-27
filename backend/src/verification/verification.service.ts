import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { IdType, NotificationType, Prisma, UserRole, VerificationStatus } from '@prisma/client';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UpdateVerificationDto } from './dto/verification.dto';

/// Private-bucket folder for every identity document.
export const VERIFICATION_FOLDER = 'verification';

/// The number formats each issuing body uses (letters upper-cased first).
const ID_NUMBER_FORMATS: Record<IdType, { pattern: RegExp; message: string }> = {
  NIN: { pattern: /^\d{11}$/, message: 'A NIN is 11 digits' },
  DRIVERS_LICENSE: { pattern: /^[A-Z0-9]{8,12}$/, message: "A driver's licence number is 8 to 12 letters and digits" },
  VOTERS_CARD: { pattern: /^[A-Z0-9]{19}$/, message: "A Voter's Card (VIN) number is 19 letters and digits" },
  INTERNATIONAL_PASSPORT: { pattern: /^[A-Z][0-9]{8}$/, message: 'A passport number is a letter followed by 8 digits' },
};

const userSelect = { id: true, fullName: true, email: true, phoneNumber: true, role: true, createdAt: true } as const;

/// Keeps the last 4 characters — for lists, where the full number isn't needed.
export function maskIdNumber(value: string | null): string | null {
  if (!value) return null;
  return value.length <= 4 ? value : `${'•'.repeat(value.length - 4)}${value.slice(-4)}`;
}

/// Identity documents given at signup (means of ID for everyone; a
/// certificate of ownership and a supporting document for landlords) and
/// their review by a moderator or super admin. Files are in the private
/// bucket and only ever leave it as short-lived signed links.
@Injectable()
export class VerificationService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
    private readonly payments: PaymentsService,
  ) {}

  signUpload(userId: string, fileName: string) {
    return this.storage.createPrivateSignedUploadUrl(userId, fileName, VERIFICATION_FOLDER);
  }

  /// What the user sees about their own submission. Never the files.
  async mine(userId: string) {
    const v = await this.prisma.identityVerification.findUnique({ where: { userId } });
    if (!v) return { status: null };
    return {
      status: v.status,
      idType: v.idType,
      idNumber: maskIdNumber(v.idNumber),
      hasCertificate: !!v.certificatePath,
      hasDocument: !!v.documentPath,
      reviewNote: v.status === VerificationStatus.REJECTED ? v.reviewNote : null,
    };
  }

  /// Saves any subset of the fields (signup sends the landlord certificate
  /// on step 1 and the rest on step 2). Once everything the role needs is
  /// there, the submission goes to PENDING for review. Changing anything
  /// after a decision sends it back for review.
  async update(userId: string, role: UserRole, dto: UpdateVerificationDto) {
    if (role !== UserRole.TENANT && role !== UserRole.LANDLORD) {
      throw new BadRequestException('Only tenants and landlords submit identity documents');
    }
    const data: Prisma.IdentityVerificationUncheckedUpdateInput = {};
    if (dto.idType !== undefined || dto.idNumber !== undefined) {
      if (!dto.idType || !dto.idNumber) throw new BadRequestException('Send both the ID type and the ID number');
      const number = dto.idNumber.replace(/[\s-]/g, '').toUpperCase();
      const format = ID_NUMBER_FORMATS[dto.idType];
      if (!format.pattern.test(number)) throw new BadRequestException(format.message);
      data.idType = dto.idType;
      data.idNumber = number;
    }
    for (const key of ['certificatePath', 'documentPath'] as const) {
      const path = dto[key];
      if (path === undefined) continue;
      if (role !== UserRole.LANDLORD) throw new BadRequestException('Only landlords upload ownership documents');
      await this.storage.assertOwnPrivateDocument(userId, path, VERIFICATION_FOLDER);
      data[key] = path;
    }

    const existing = await this.prisma.identityVerification.findUnique({ where: { userId } });
    const merged = { ...existing, ...data } as { idType?: IdType | null; idNumber?: string | null; certificatePath?: string | null; documentPath?: string | null };
    const complete = !!merged.idType && !!merged.idNumber && (role !== UserRole.LANDLORD || (!!merged.certificatePath && !!merged.documentPath));
    const changed = Object.keys(data).length > 0;
    if (complete && (changed || existing?.status === VerificationStatus.INCOMPLETE || !existing)) {
      data.status = VerificationStatus.PENDING;
      data.submittedAt = new Date();
      data.reviewedById = null;
      data.reviewNote = null;
      data.reviewedAt = null;
    } else if (!complete) {
      data.status = VerificationStatus.INCOMPLETE;
    }

    await this.prisma.identityVerification.upsert({
      where: { userId },
      create: { ...(data as Prisma.IdentityVerificationUncheckedCreateInput), userId },
      update: data,
    });
    return this.mine(userId);
  }

  // --- Admin -----------------------------------------------------------------

  async list(status?: string) {
    const valid = Object.values(VerificationStatus) as string[];
    const where: Prisma.IdentityVerificationWhereInput =
      status && valid.includes(status) ? { status: status as VerificationStatus } : { status: { not: VerificationStatus.INCOMPLETE } };
    const rows = await this.prisma.identityVerification.findMany({
      where,
      include: { user: { select: userSelect } },
      orderBy: [{ submittedAt: 'asc' }, { createdAt: 'asc' }],
      take: 300,
    });
    return rows.map((v) => ({
      userId: v.userId,
      user: v.user,
      status: v.status,
      idType: v.idType,
      idNumber: maskIdNumber(v.idNumber),
      hasCertificate: !!v.certificatePath,
      hasDocument: !!v.documentPath,
      submittedAt: v.submittedAt,
      reviewedAt: v.reviewedAt,
    }));
  }

  pendingCount() {
    return this.prisma.identityVerification.count({ where: { status: VerificationStatus.PENDING } });
  }

  /// Full record for review: the whole ID number and 10-minute links to the files.
  async detail(userId: string) {
    const v = await this.prisma.identityVerification.findUnique({
      where: { userId },
      include: { user: { select: userSelect }, reviewedBy: { select: { id: true, fullName: true, email: true } } },
    });
    if (!v) return null;
    const link = (path: string | null) => (path ? this.storage.signedViewUrl(path, 600) : Promise.resolve(null));
    const [certificateUrl, documentUrl] = await Promise.all([link(v.certificatePath), link(v.documentPath)]);
    return {
      userId: v.userId,
      user: v.user,
      status: v.status,
      idType: v.idType,
      idNumber: v.idNumber,
      certificateUrl,
      certificateIsPdf: v.certificatePath?.toLowerCase().endsWith('.pdf') ?? false,
      documentUrl,
      documentIsPdf: v.documentPath?.toLowerCase().endsWith('.pdf') ?? false,
      submittedAt: v.submittedAt,
      reviewedBy: v.reviewedBy,
      reviewNote: v.reviewNote,
      reviewedAt: v.reviewedAt,
      linksExpireInSeconds: 600,
    };
  }

  async review(adminId: string, userId: string, decision: 'APPROVE' | 'REJECT', note?: string) {
    const cleanNote = note?.trim() || null;
    if (decision === 'REJECT' && (!cleanNote || cleanNote.length < 10)) {
      throw new BadRequestException('Tell the user what to fix (at least 10 characters)');
    }
    const updated = await this.prisma.identityVerification.updateMany({
      where: { userId, status: VerificationStatus.PENDING },
      data: {
        status: decision === 'APPROVE' ? VerificationStatus.APPROVED : VerificationStatus.REJECTED,
        reviewedById: adminId,
        reviewNote: cleanNote,
        reviewedAt: new Date(),
      },
    });
    if (updated.count === 0) {
      const exists = await this.prisma.identityVerification.findUnique({ where: { userId }, select: { id: true } });
      if (!exists) throw new NotFoundException('This user has not submitted identity documents');
      throw new ConflictException('This submission is not waiting for review (already decided, or incomplete)');
    }
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true } });
    const approved = decision === 'APPROVE';
    const title = approved ? 'Your identity has been verified' : 'Your identity documents need attention';
    const body = approved
      ? 'HomeServant has reviewed and verified your identity documents.'
      : `HomeServant couldn't verify your identity documents: ${cleanNote}`;
    await this.notifications.create(userId, NotificationType.BOOKING_STATUS, title, body);
    await this.mail.send(user.email, title, `<p>${escapeHtml(body)}</p>`, body);
    if (approved) {
      // Any payouts held while they were unverified (Platform Controls).
      await this.payments.releaseHeldPayoutsForLandlord(userId);
    }
    return this.detail(userId);
  }
}

function escapeHtml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
