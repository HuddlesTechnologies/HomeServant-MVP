import { BadRequestException, ConflictException, Inject, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { IdCheckStatus, IdType, NotificationType, Prisma, UserRole, VerificationStatus } from '@prisma/client';
import { ID_CHECK_PROVIDER } from '../id-check/id-check.constants';
import { IdCheckProvider, IdCheckResult } from '../id-check/id-check-provider.interface';
import { MailService } from '../mail/mail.service';
import { NotificationsService } from '../notifications/notifications.service';
import { PaymentsService } from '../payments/payments.service';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { UpdateVerificationDto } from './dto/verification.dto';
import { escapeHtml } from '../common/escape-html';

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

/// Everything about an automated check, cleared as a set. Written when a
/// new number is submitted so a stale result can never sit next to it.
const CLEARED_ID_CHECK = {
  idCheckStatus: IdCheckStatus.NOT_RUN,
  idCheckProvider: null,
  idCheckReference: null,
  idCheckName: null,
  idCheckDetail: null,
  idCheckedAt: null,
} as const;

/// Keeps the last 4 characters — for lists, where the full number isn't needed.
export function maskIdNumber(value: string | null): string | null {
  if (!value) return null;
  return value.length <= 4 ? value : `${'•'.repeat(value.length - 4)}${value.slice(-4)}`;
}

/// Identity documents given at signup (means of ID for everyone; a
/// certificate of ownership and a supporting document for landlords) and
/// their review by a moderator or super admin. Files are in the private
/// bucket and only ever leave it as short-lived signed links.
///
/// Every ID number submitted is also checked against the body that issued
/// it (see IdCheckProvider). A tenant whose number exists and carries
/// their name is verified there and then, without waiting for a moderator;
/// every other outcome — mismatch, no record, an unsupported ID, a
/// provider that was down — leaves the submission PENDING with the result
/// recorded, so a human decides with the registry's answer in front of
/// them. Landlords are never auto-verified: their certificate of ownership
/// and supporting document are exactly the part no ID lookup can vouch for.
@Injectable()
export class VerificationService {
  private readonly logger = new Logger('Verification');

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly notifications: NotificationsService,
    private readonly mail: MailService,
    private readonly payments: PaymentsService,
    @Inject(ID_CHECK_PROVIDER) private readonly idCheck: IdCheckProvider,
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
      /// Whether their number was confirmed with the issuing body. Not the
      /// provider's message — that can name the mismatch, which is a
      /// reviewer's business, not a hint for someone guessing at numbers.
      idCheckStatus: v.idCheckStatus,
      hasCertificate: !!v.certificatePath,
      hasDocument: !!v.documentPath,
      reviewNote: v.status === VerificationStatus.REJECTED ? v.reviewNote : null,
    };
  }

  /// Saves any subset of the fields (signup sends the landlord certificate
  /// on step 1 and the rest on step 2). Once everything the role needs is
  /// there, the submission goes to PENDING, the ID number is checked with
  /// the issuing body, and a tenant with a clean match is verified
  /// immediately. Changing anything after a decision sends it back for
  /// review.
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
    const idChanged = (data.idType !== undefined && data.idType !== existing?.idType) || (data.idNumber !== undefined && data.idNumber !== existing?.idNumber);
    // A new number invalidates whatever the last check said about the old
    // one, including an approval that came out of it.
    if (idChanged) Object.assign(data, CLEARED_ID_CHECK, { autoApproved: false });

    const merged = { ...existing, ...data } as { idType?: IdType | null; idNumber?: string | null; certificatePath?: string | null; documentPath?: string | null };
    const complete = !!merged.idType && !!merged.idNumber && (role !== UserRole.LANDLORD || (!!merged.certificatePath && !!merged.documentPath));
    const changed = Object.keys(data).length > 0;
    if (complete && (changed || existing?.status === VerificationStatus.INCOMPLETE || !existing)) {
      data.status = VerificationStatus.PENDING;
      data.submittedAt = new Date();
      data.reviewedById = null;
      data.reviewNote = null;
      data.reviewedAt = null;
      data.autoApproved = false;
    } else if (!complete) {
      data.status = VerificationStatus.INCOMPLETE;
    }

    await this.prisma.identityVerification.upsert({
      where: { userId },
      create: { ...(data as Prisma.IdentityVerificationUncheckedCreateInput), userId },
      update: data,
    });

    // Worth a lookup once there's a complete submission and either the
    // number is new or the last attempt never produced an answer. A
    // MISMATCH or NOT_FOUND on an unchanged number would only come back
    // the same, so resubmitting the same digits doesn't spend another
    // lookup — a moderator can force one from the console.
    if (data.status === VerificationStatus.PENDING) {
      const previous = existing?.idCheckStatus ?? IdCheckStatus.NOT_RUN;
      const worthChecking = idChanged || previous === IdCheckStatus.NOT_RUN || previous === IdCheckStatus.ERROR;
      if (worthChecking) {
        await this.runIdCheck(userId, role);
      } else {
        // The number is the one already checked, so the old answer still
        // stands — including a match, which would otherwise be thrown away
        // by the reset above and leave a verified tenant queued behind a
        // resubmission that changed nothing about their ID.
        await this.approveIfClean(userId, role, previous, existing?.idCheckProvider ?? null);
      }
    }
    return this.mine(userId);
  }

  // --- The automated check ----------------------------------------------------

  /// Looks the submitted number up with the issuing body, records the
  /// answer, and verifies a tenant outright on a clean match. Never
  /// throws: this runs inside signup, and an ID provider being down must
  /// leave someone with a pending submission, not a failed signup.
  private async runIdCheck(userId: string, role: UserRole): Promise<void> {
    const v = await this.prisma.identityVerification.findUnique({
      where: { userId },
      select: { idType: true, idNumber: true, status: true },
    });
    if (!v?.idType || !v.idNumber) return;

    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { firstName: true, lastName: true, fullName: true, dateOfBirth: true },
    });
    if (!user) return;

    let result: IdCheckResult;
    try {
      result = await this.idCheck.check({
        idType: v.idType,
        idNumber: v.idNumber,
        subject: { firstName: user.firstName, lastName: user.lastName, fullName: user.fullName, dateOfBirth: user.dateOfBirth },
      });
    } catch (error) {
      // The interface says implementations don't throw. If one does, it
      // still must not take signup down with it.
      this.logger.error(`ID check threw for ${v.idType}: ${error instanceof Error ? error.message : 'unknown error'}`);
      result = {
        provider: this.idCheck.name,
        outcome: IdCheckStatus.ERROR,
        detail: 'The ID check could not be completed. This needs a manual review, or run the check again.',
      };
    }

    await this.prisma.identityVerification.update({
      where: { userId },
      data: {
        idCheckStatus: result.outcome,
        idCheckProvider: result.provider,
        idCheckReference: result.reference ?? null,
        idCheckName: result.name ?? null,
        idCheckDetail: result.detail,
        idCheckedAt: new Date(),
      },
    });

    await this.approveIfClean(userId, role, result.outcome, result.provider);
  }

  /// Verifies a pending submission off a clean check. Only a tenant, and
  /// only on a MATCH: a landlord's certificate of ownership still needs
  /// eyes on it whatever the registry says about their ID number.
  private async approveIfClean(userId: string, role: UserRole, outcome: IdCheckStatus, provider: string | null): Promise<void> {
    if (role !== UserRole.TENANT || outcome !== IdCheckStatus.MATCH) return;
    const approved = await this.prisma.identityVerification.updateMany({
      where: { userId, status: VerificationStatus.PENDING },
      data: {
        status: VerificationStatus.APPROVED,
        autoApproved: true,
        reviewedById: null,
        reviewNote: null,
        reviewedAt: new Date(),
      },
    });
    if (approved.count === 0) return;
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId }, select: { email: true } });
    this.logger.log(`Verified ${userId} automatically: ID confirmed by ${provider ?? 'the ID check'}`);
    await this.announceDecision(userId, user.email, true, null, true);
  }

  /// A moderator forcing another lookup — for a submission whose check
  /// errored, or one made before a provider was configured. Costs a
  /// provider call, so it's a deliberate button rather than something the
  /// queue does on its own.
  async recheck(userId: string) {
    const v = await this.prisma.identityVerification.findUnique({
      where: { userId },
      select: { idType: true, idNumber: true, user: { select: { role: true } } },
    });
    if (!v) throw new NotFoundException('This user has not submitted identity documents');
    if (!v.idType || !v.idNumber) throw new BadRequestException('There is no ID number on this submission to check');
    await this.runIdCheck(userId, v.user.role);
    return this.detail(userId);
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
      idCheckStatus: v.idCheckStatus,
      hasCertificate: !!v.certificatePath,
      hasDocument: !!v.documentPath,
      submittedAt: v.submittedAt,
      reviewedAt: v.reviewedAt,
      autoApproved: v.autoApproved,
    }));
  }

  pendingCount() {
    return this.prisma.identityVerification.count({ where: { status: VerificationStatus.PENDING } });
  }

  /// Full record for review: the whole ID number, what the issuing body
  /// said about it, and 10-minute links to the files.
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
      idCheckStatus: v.idCheckStatus,
      idCheckProvider: v.idCheckProvider,
      idCheckReference: v.idCheckReference,
      idCheckName: v.idCheckName,
      idCheckDetail: v.idCheckDetail,
      idCheckedAt: v.idCheckedAt,
      certificateUrl,
      certificateIsPdf: v.certificatePath?.toLowerCase().endsWith('.pdf') ?? false,
      documentUrl,
      documentIsPdf: v.documentPath?.toLowerCase().endsWith('.pdf') ?? false,
      submittedAt: v.submittedAt,
      reviewedBy: v.reviewedBy,
      reviewNote: v.reviewNote,
      reviewedAt: v.reviewedAt,
      autoApproved: v.autoApproved,
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
        autoApproved: false,
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
    await this.announceDecision(userId, user.email, decision === 'APPROVE', cleanNote, false);
    return this.detail(userId);
  }

  /// Telling someone their identity was (or wasn't) verified — the same
  /// notification, email and held-payout release whether a moderator
  /// decided it or a clean ID check did.
  private async announceDecision(userId: string, email: string, approved: boolean, note: string | null, automatic: boolean): Promise<void> {
    const title = approved ? 'Your identity has been verified' : 'Your identity documents need attention';
    const body = approved
      ? automatic
        ? 'HomeServant checked your ID with the body that issued it and your identity is now verified.'
        : 'HomeServant has reviewed and verified your identity documents.'
      : `HomeServant couldn't verify your identity documents: ${note}`;
    await this.notifications.create(userId, NotificationType.BOOKING_STATUS, title, body);
    await this.mail.send(email, title, `<p>${escapeHtml(body)}</p>`, body);
    if (approved) {
      // Any payouts held while they were unverified (Platform Controls).
      await this.payments.releaseHeldPayoutsForLandlord(userId);
    }
  }
}

