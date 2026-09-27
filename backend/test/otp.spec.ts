import { BadRequestException, ServiceUnavailableException } from '@nestjs/common';
import { OtpPurpose, PrismaClient } from '@prisma/client';
import { plainToInstance } from 'class-transformer';
import { LoginDto } from '../src/auth/dto/login.dto';
import { ResendOtpDto } from '../src/auth/dto/resend-otp.dto';
import { SignupDto } from '../src/auth/dto/signup.dto';
import { OtpService } from '../src/otp/otp.service';
import { ResendOtpProvider } from '../src/otp/resend-otp.provider';
import { resetDb, testDbUrl, testPrisma } from './helpers';

const describeDb = testDbUrl ? describe : describe.skip;

describeDb('sign-up codes (real Postgres)', () => {
  let prisma: PrismaClient;
  let sent: string[];
  let otp: OtpService;

  beforeAll(() => {
    prisma = testPrisma();
  });
  afterAll(async () => {
    await prisma.$disconnect();
  });
  beforeEach(async () => {
    await resetDb(prisma);
    sent = [];
    otp = new OtpService(prisma as never, { send: async (_to: string, code: string) => void sent.push(code) } as never);
  });

  it('still accepts the first code after a resend, and then neither works again', async () => {
    await otp.issue('ada@example.com', OtpPurpose.SIGNUP);
    await otp.issue('ada@example.com', OtpPurpose.SIGNUP); // "Resend"
    const [first, second] = sent;
    await expect(otp.verify('ada@example.com', OtpPurpose.SIGNUP, first)).resolves.toBeUndefined();
    await expect(otp.verify('ada@example.com', OtpPurpose.SIGNUP, second)).rejects.toThrow(/expired/);
  });

  it('caps wrong guesses, and a fresh code resets the count', async () => {
    await otp.issue('ada@example.com', OtpPurpose.SIGNUP);
    const wrong = sent[0] === '1234' ? '4321' : '1234';
    for (let i = 0; i < 5; i++) {
      await expect(otp.verify('ada@example.com', OtpPurpose.SIGNUP, wrong)).rejects.toThrow(/Incorrect code/);
    }
    await expect(otp.verify('ada@example.com', OtpPurpose.SIGNUP, sent[0])).rejects.toThrow(/Too many/);
    await otp.issue('ada@example.com', OtpPurpose.SIGNUP);
    await expect(otp.verify('ada@example.com', OtpPurpose.SIGNUP, sent[1])).resolves.toBeUndefined();
  });

  it('does not accept a code issued for another purpose', async () => {
    await otp.issue('ada@example.com', OtpPurpose.LOGIN_2FA);
    await expect(otp.verify('ada@example.com', OtpPurpose.SIGNUP, sent[0])).rejects.toThrow(BadRequestException);
  });
});

describe('sending codes through Resend', () => {
  function providerWith(results: Array<{ error: { name?: string; message: string } | null }>) {
    const provider = new ResendOtpProvider('re_test', 'HomeServant <otp@example.com>');
    const calls = { count: 0 };
    (provider as unknown as { client: unknown }).client = {
      emails: { send: async () => results[Math.min(calls.count++, results.length - 1)] },
    };
    return { provider, calls };
  }

  it('retries a brief rate-limit failure and then succeeds', async () => {
    const { provider, calls } = providerWith([
      { error: { name: 'rate_limit_exceeded', message: 'Too many requests' } },
      { error: null },
    ]);
    await expect(provider.send('ada@example.com', '1234')).resolves.toBeUndefined();
    expect(calls.count).toBe(2);
  });

  it('gives up straight away on a permanent problem, with a clear message', async () => {
    const { provider, calls } = providerWith([{ error: { name: 'validation_error', message: 'Invalid `to` field' } }]);
    await expect(provider.send('bad', '1234')).rejects.toThrow(ServiceUnavailableException);
    await expect(provider.send('bad', '1234')).rejects.toThrow(/try again in a minute/);
    expect(calls.count).toBe(2);
  });
});

describe('email addresses ignore case and spaces', () => {
  it('lower-cases and trims every email the API receives', () => {
    expect(plainToInstance(SignupDto, { email: '  Ada@Example.COM ' }).email).toBe('ada@example.com');
    expect(plainToInstance(LoginDto, { email: 'ADA@example.com' }).email).toBe('ada@example.com');
    expect(plainToInstance(ResendOtpDto, { email: 'Ada@Example.com' }).email).toBe('ada@example.com');
  });
});
