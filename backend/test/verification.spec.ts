import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { IdCheckStatus, PrismaClient, UserRole } from '@prisma/client';
import { IdCheckResult } from '../src/id-check/id-check-provider.interface';
import { maskIdNumber, VerificationService } from '../src/verification/verification.service';
import { fakeMail, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('identity verification (real Postgres)', () => {
  let prisma: PrismaClient;
  let mail: ReturnType<typeof fakeMail>;
  let notes: { userId: string; title: string }[];
  let service: VerificationService;
  /// Queued answers for the ID check, so each test says what the registry
  /// came back with. Empty means UNSUPPORTED — what a service with no
  /// provider configured does, and therefore the default everywhere a
  /// test isn't specifically about the check.
  let idCheckAnswers: Partial<IdCheckResult>[];
  let idCheckCalls: number;

  // Mirrors StorageService's rule: only paths in the user's own folder.
  const storage = {
    async assertOwnPrivateDocument(userId: string, path: string, folder: string) {
      if (!path.startsWith(`${folder}/${userId}/`)) throw new BadRequestException('That file was not uploaded by this account');
    },
    async signedViewUrl(path: string) {
      return `https://signed.example/${path}?token=t`;
    },
    async createPrivateSignedUploadUrl() {
      return { path: 'x', signedUrl: 'y', token: 'z' };
    },
  };

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    mail = fakeMail();
    notes = [];
    const notifications = { create: async (userId: string, _t: unknown, title: string) => void notes.push({ userId, title }) };
    idCheckAnswers = [];
    idCheckCalls = 0;
    const idCheck = {
      name: 'fake',
      check: async (): Promise<IdCheckResult> => {
        idCheckCalls++;
        const queued = idCheckAnswers.shift();
        return { provider: 'fake', outcome: IdCheckStatus.UNSUPPORTED, detail: 'not checked', ...queued };
      },
    };
    service = new VerificationService(
      prisma as never,
      storage as never,
      notifications as never,
      mail as never,
      { releaseHeldPayoutsForLandlord: async () => 0 } as never,
      idCheck,
    );
  });

  it('checks the ID number format for the chosen ID type', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    await expect(service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '1234' })).rejects.toBeInstanceOf(BadRequestException);
    const saved = await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '123 4567 8901' });
    expect(saved.status).toBe('PENDING'); // a tenant only needs the ID
    expect(saved.idNumber).toBe('•••••••8901');
  });

  it('a landlord stays incomplete until the ID, certificate and document are all in', async () => {
    const landlord = await makeUser(prisma, UserRole.LANDLORD);
    const mine = (p: string) => `verification/${landlord.id}/${p}`;
    expect((await service.update(landlord.id, UserRole.LANDLORD, { certificatePath: mine('c.pdf') })).status).toBe('INCOMPLETE');
    expect((await service.update(landlord.id, UserRole.LANDLORD, { idType: 'INTERNATIONAL_PASSPORT', idNumber: 'a12345678' })).status).toBe('INCOMPLETE');
    await expect(
      service.update(landlord.id, UserRole.LANDLORD, { documentPath: 'verification/someone-else/d.jpg' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect((await service.update(landlord.id, UserRole.LANDLORD, { documentPath: mine('d.jpg') })).status).toBe('PENDING');

    const detail = await service.detail(landlord.id);
    expect(detail!.idNumber).toBe('A12345678');
    expect(detail!.certificateUrl).toContain('signed.example');
    expect(detail!.certificateIsPdf).toBe(true);
    expect((await service.list('PENDING')).map((r) => r.userId)).toEqual([landlord.id]);
  });

  it('tenants cannot attach ownership documents', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    await expect(
      service.update(tenant.id, UserRole.TENANT, { certificatePath: `verification/${tenant.id}/c.pdf` }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('review: reject needs a note, is decided once, and resubmitting goes back to pending', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
    await service.update(tenant.id, UserRole.TENANT, { idType: 'VOTERS_CARD', idNumber: '90F5B1234567890123A' });
    await expect(service.review(admin.id, tenant.id, 'REJECT')).rejects.toBeInstanceOf(BadRequestException);
    const rejected = await service.review(admin.id, tenant.id, 'REJECT', 'The photo of the card is blurry.');
    expect(rejected!.status).toBe('REJECTED');
    expect(notes.some((n) => n.userId === tenant.id)).toBe(true);
    await expect(service.review(admin.id, tenant.id, 'APPROVE')).rejects.toBeInstanceOf(ConflictException);
    expect((await service.mine(tenant.id)).reviewNote).toBe('The photo of the card is blurry.');

    expect((await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '12345678901' })).status).toBe('PENDING');
    const approved = await service.review(admin.id, tenant.id, 'APPROVE');
    expect(approved!.status).toBe('APPROVED');
    expect(approved!.reviewedBy!.id).toBe(admin.id);
  });

  it('a tenant whose ID matches the registry is verified there and then', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT, { fullName: 'Chinedu Okonkwo' });
    idCheckAnswers.push({ outcome: IdCheckStatus.MATCH, name: 'CHINEDU OKONKWO', reference: 'ref-1', detail: '2 of 2 name parts match the name on record' });

    const mine = await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '12345678901' });
    expect(mine.status).toBe('APPROVED');
    expect(mine.idCheckStatus).toBe(IdCheckStatus.MATCH);

    const detail = await service.detail(tenant.id);
    expect(detail!.autoApproved).toBe(true);
    // Nobody reviewed it, so there is no reviewer to show.
    expect(detail!.reviewedBy).toBeNull();
    expect(detail!.idCheckName).toBe('CHINEDU OKONKWO');
    expect(detail!.idCheckReference).toBe('ref-1');
    // They're told, the same as when a moderator approves.
    expect(notes.some((n) => n.userId === tenant.id && n.title === 'Your identity has been verified')).toBe(true);
    expect(mail.sent).toHaveLength(1);
  });

  it('never verifies a landlord on the ID check alone — the ownership documents still need eyes', async () => {
    const landlord = await makeUser(prisma, UserRole.LANDLORD, { fullName: 'Chinedu Okonkwo' });
    const mine = (p: string) => `verification/${landlord.id}/${p}`;
    idCheckAnswers.push({ outcome: IdCheckStatus.MATCH, name: 'CHINEDU OKONKWO' });

    await service.update(landlord.id, UserRole.LANDLORD, { certificatePath: mine('c.pdf'), documentPath: mine('d.jpg') });
    const submitted = await service.update(landlord.id, UserRole.LANDLORD, { idType: 'NIN', idNumber: '12345678901' });
    expect(submitted.status).toBe('PENDING');
    expect(submitted.idCheckStatus).toBe(IdCheckStatus.MATCH);
    expect((await service.detail(landlord.id))!.autoApproved).toBe(false);
    expect(notes).toHaveLength(0);
  });

  it('records a mismatch for the reviewer instead of deciding anything', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT, { fullName: 'Chinedu Okonkwo' });
    idCheckAnswers.push({ outcome: IdCheckStatus.MISMATCH, name: 'MUSA IBRAHIM', detail: 'Only 0 name parts match the name on record (2 needed)' });

    expect((await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '12345678901' })).status).toBe('PENDING');
    const detail = await service.detail(tenant.id);
    expect(detail!.idCheckStatus).toBe(IdCheckStatus.MISMATCH);
    expect(detail!.idCheckName).toBe('MUSA IBRAHIM');
    // The mismatch itself is never shown to the person who submitted it.
    expect(await service.mine(tenant.id)).not.toHaveProperty('idCheckName');
  });

  it('a provider that is down leaves a normal pending submission, and the check can be run again', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT, { fullName: 'Chinedu Okonkwo' });
    idCheckAnswers.push({ outcome: IdCheckStatus.ERROR, detail: 'The ID check service could not be reached.' });

    expect((await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '12345678901' })).status).toBe('PENDING');
    expect((await service.detail(tenant.id))!.idCheckStatus).toBe(IdCheckStatus.ERROR);

    idCheckAnswers.push({ outcome: IdCheckStatus.MATCH, name: 'CHINEDU OKONKWO' });
    const rechecked = await service.recheck(tenant.id);
    expect(rechecked!.status).toBe('APPROVED');
    expect(rechecked!.autoApproved).toBe(true);
  });

  it('will not check a user who has submitted nothing', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT);
    await expect(service.recheck(tenant.id)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('keeps a verified tenant verified when they resubmit the same ID', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT, { fullName: 'Chinedu Okonkwo' });
    idCheckAnswers.push({ outcome: IdCheckStatus.MATCH, name: 'CHINEDU OKONKWO' });
    expect((await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '12345678901' })).status).toBe('APPROVED');

    // Same number again: no reason to pay for another lookup, and no
    // reason to put them back in the queue either.
    expect((await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '12345678901' })).status).toBe('APPROVED');
    expect(idCheckCalls).toBe(1);
    expect((await service.detail(tenant.id))!.autoApproved).toBe(true);
  });

  it('does not spend a second lookup on a number it has already judged', async () => {
    const tenant = await makeUser(prisma, UserRole.TENANT, { fullName: 'Chinedu Okonkwo' });
    const admin = await makeUser(prisma, UserRole.ADMIN, { adminLevel: 'MODERATOR' });
    idCheckAnswers.push({ outcome: IdCheckStatus.NOT_FOUND, detail: 'No record of this ID number was found.' });
    await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '12345678901' });
    await service.review(admin.id, tenant.id, 'REJECT', 'We could not find that NIN — check the digits.');
    expect(idCheckCalls).toBe(1);

    // Same digits again: the registry would only say the same thing.
    await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '123 4567 8901' });
    expect(idCheckCalls).toBe(1);
    expect((await service.detail(tenant.id))!.idCheckStatus).toBe(IdCheckStatus.NOT_FOUND);

    // A different number is a different question, and the old answer goes.
    idCheckAnswers.push({ outcome: IdCheckStatus.MATCH, name: 'CHINEDU OKONKWO' });
    expect((await service.update(tenant.id, UserRole.TENANT, { idType: 'NIN', idNumber: '10987654321' })).status).toBe('APPROVED');
    expect(idCheckCalls).toBe(2);
  });

  it('a landlord adding a missing document does not pay for another lookup', async () => {
    const landlord = await makeUser(prisma, UserRole.LANDLORD, { fullName: 'Chinedu Okonkwo' });
    const mine = (p: string) => `verification/${landlord.id}/${p}`;
    await service.update(landlord.id, UserRole.LANDLORD, { idType: 'NIN', idNumber: '12345678901', certificatePath: mine('c.pdf'), documentPath: mine('d.jpg') });
    expect(idCheckCalls).toBe(1);
    await service.update(landlord.id, UserRole.LANDLORD, { documentPath: mine('d2.jpg') });
    expect(idCheckCalls).toBe(1);
  });

  it('masks all but the last four characters', () => {
    expect(maskIdNumber('12345678901')).toBe('•••••••8901');
    expect(maskIdNumber(null)).toBeNull();
  });
});
