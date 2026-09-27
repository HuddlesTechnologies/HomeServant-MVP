import { BadRequestException, ConflictException } from '@nestjs/common';
import { PrismaClient, UserRole } from '@prisma/client';
import { maskIdNumber, VerificationService } from '../src/verification/verification.service';
import { fakeMail, makeUser, resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('identity verification (real Postgres)', () => {
  let prisma: PrismaClient;
  let mail: ReturnType<typeof fakeMail>;
  let notes: { userId: string; title: string }[];
  let service: VerificationService;

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
    service = new VerificationService(prisma as never, storage as never, notifications as never, mail as never, { releaseHeldPayoutsForLandlord: async () => 0 } as never);
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

  it('masks all but the last four characters', () => {
    expect(maskIdNumber('12345678901')).toBe('•••••••8901');
    expect(maskIdNumber(null)).toBeNull();
  });
});
