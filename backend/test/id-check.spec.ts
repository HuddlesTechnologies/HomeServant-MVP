import { IdCheckStatus } from '@prisma/client';
import { ConsoleIdCheckProvider } from '../src/id-check/console-id-check.provider';
import { IdCheckRequest } from '../src/id-check/id-check-provider.interface';
import { compareNames, nameTokens, subjectDisplayName } from '../src/id-check/name-match';
import { PremblyIdCheckProvider } from '../src/id-check/prembly-id-check.provider';

/// No database needed: name comparison is pure, and the provider is
/// exercised against a stubbed `fetch` rather than Prembly itself.
describe('name matching', () => {
  it('ignores case, accents, punctuation, titles and initials', () => {
    expect(nameTokens('  Chief Adé-Bọ́lá  O. OKONKWO ')).toEqual(['ade', 'bola', 'okonkwo']);
    expect(nameTokens(null)).toEqual([]);
  });

  it('matches regardless of the order the parts are written in', () => {
    expect(compareNames('OKONKWO Chinedu', 'Chinedu Okonkwo').matched).toBe(true);
    expect(compareNames('Chinedu Emeka Okonkwo', 'Chinedu Okonkwo').matched).toBe(true);
  });

  it('forgives one typo in a long name but not in a short one', () => {
    expect(compareNames('Chukwuemeka Okonkwo', 'Chukwuemeke Okonkwo').matched).toBe(true);
    expect(compareNames('Femi Okonkwo', 'Remi Okonkwo').matched).toBe(false);
  });

  it('refuses two people who only share a surname', () => {
    const result = compareNames('Emeka Okonkwo', 'Chidi Okonkwo');
    expect(result.matched).toBe(false);
    expect(result.reason).toContain('1 name part');
  });

  it('spends each name part on record only once', () => {
    expect(compareNames('Bello Ibrahim', 'Bello Bello').matched).toBe(false);
  });

  it('needs the single part to match when one side has only one', () => {
    expect(compareNames('Okonkwo', 'Chinedu Okonkwo').matched).toBe(true);
    expect(compareNames('Okonkwo', 'Chinedu Eze').matched).toBe(false);
  });

  it('never matches when a name is missing entirely', () => {
    expect(compareNames('', 'Chinedu Okonkwo').matched).toBe(false);
    expect(compareNames('Chinedu Okonkwo', '   ').matched).toBe(false);
  });

  it('compares against the fullest name on the account, without repeating parts', () => {
    expect(subjectDisplayName({ firstName: 'Chinedu', lastName: 'Okonkwo', fullName: 'Chinedu Emeka Okonkwo' })).toBe('Chinedu Emeka Okonkwo');
    expect(subjectDisplayName({ firstName: 'Chinedu', lastName: 'Okonkwo', fullName: 'Chinedu' })).toBe('Chinedu Okonkwo');
    expect(subjectDisplayName({ firstName: null, lastName: null, fullName: null })).toBeNull();
  });
});

describe('the console provider', () => {
  it('checks nothing, so a submission is left for a moderator', async () => {
    const result = await new ConsoleIdCheckProvider().check(request('NIN', '12345678901'));
    expect(result.outcome).toBe(IdCheckStatus.UNSUPPORTED);
    expect(result.provider).toBe('console');
  });
});

describe('the Prembly provider', () => {
  const realFetch = global.fetch;
  let calls: { url: string; headers: Record<string, string>; body: Record<string, unknown> }[];

  /// Answers the next call with [body] under HTTP [status].
  function stubFetch(body: unknown, status = 200) {
    global.fetch = (async (url: string, init: RequestInit) => {
      calls.push({
        url: String(url),
        headers: init.headers as Record<string, string>,
        body: JSON.parse(String(init.body)) as Record<string, unknown>,
      });
      return { status, json: async () => body } as Response;
    }) as unknown as typeof fetch;
  }

  const provider = () => new PremblyIdCheckProvider('secret-key', 'app-1', 'https://api.prembly.com/identitypass/');

  beforeEach(() => {
    calls = [];
  });
  afterEach(() => {
    global.fetch = realFetch;
  });

  it('sends an 11-digit NIN as number_nin to the live host, authenticated by key', async () => {
    // The live NIN envelope: names under `data`, and an empty `nin_data`
    // alongside it (measured against their current API docs).
    stubFetch({
      status: true,
      response_code: '00',
      message: 'National Identity Number (NIN) verification successful',
      detail: 'National Identity Number (NIN) verification successful',
      data: { firstname: 'CHINEDU', middlename: 'EMEKA', surname: 'OKONKWO', photo: 'BASE64', nin: '12345678901' },
      billing_info: { was_charged: true, amount: '100.00' },
      verification: { status: 'VERIFIED', reference: 'ref-1' },
      nin_data: {},
    });
    const result = await provider().check(request('NIN', '12345678901'));

    expect(calls[0].url).toBe('https://api.prembly.com/identitypass/verification/vnin');
    expect(calls[0].body).toEqual({ number_nin: '12345678901' });
    expect(calls[0].headers['x-api-key']).toBe('secret-key');
    expect(calls[0].headers['app-id']).toBe('app-1');
    expect(result.outcome).toBe(IdCheckStatus.MATCH);
    expect(result.name).toBe('CHINEDU EMEKA OKONKWO');
    expect(result.reference).toBe('ref-1');
    // Nothing from the photo or the billing block leaks into what we store.
    expect(JSON.stringify(result)).not.toContain('BASE64');
    expect(JSON.stringify(result)).not.toContain('100.00');
  });

  it('omits app-id entirely when none is configured', async () => {
    stubFetch({ status: true, detail: 'ok', data: { firstname: 'Chinedu', surname: 'Okonkwo' } });
    await new PremblyIdCheckProvider('secret-key').check(request('NIN', '12345678901'));
    expect(calls[0].url).toBe('https://api.prembly.com/identitypass/verification/vnin');
    expect(calls[0].headers).not.toHaveProperty('app-id');
  });

  it('reads a name however that endpoint happens to spell it', async () => {
    stubFetch({ status: true, detail: 'ok', data: { firstName: 'Chinedu', lastName: 'Okonkwo' } });
    expect((await provider().check(request('DRIVERS_LICENSE', 'AAD23208212298'))).outcome).toBe(IdCheckStatus.MATCH);
    expect(calls[0].url).toBe('https://api.prembly.com/identitypass/verification/drivers_license');
    expect(calls[0].body).toEqual({ number: 'AAD23208212298', dob: '1995-04-17' });

    stubFetch({ status: true, detail: 'ok', data: { fullName: 'OKONKWO CHINEDU' } });
    expect((await provider().check(request('VOTERS_CARD', '90F5B1234567890123A'))).outcome).toBe(IdCheckStatus.MATCH);
    expect(calls[1].body).toEqual({ number: '90F5B1234567890123A', last_name: 'Okonkwo', first_name: 'Chinedu', dob: '1995-04-17' });

    stubFetch({ status: true, detail: 'ok', data: { first_name: 'Chinedu', last_name: 'Okonkwo' } });
    expect((await provider().check(request('INTERNATIONAL_PASSPORT', 'A12345678'))).outcome).toBe(IdCheckStatus.MATCH);
    expect(calls[2].body).toEqual({ number: 'A12345678', last_name: 'Okonkwo' });

    // Some countries answer with one whole name instead of parts.
    stubFetch({ status: true, detail: 'ok', data: { identity_name: 'Chinedu Okonkwo' } });
    expect((await provider().check(request('DRIVERS_LICENSE', 'AAD23208212298'))).name).toBe('Chinedu Okonkwo');
  });

  it('still reads the legacy payload keys', async () => {
    stubFetch({ status: true, detail: 'ok', frsc_data: { firstName: 'Chinedu', lastName: 'Okonkwo' } });
    expect((await provider().check(request('DRIVERS_LICENSE', 'AAD23208212298'))).outcome).toBe(IdCheckStatus.MATCH);
  });

  it('is a mismatch when the registry holds the number under another name', async () => {
    stubFetch({ status: true, detail: 'Verification Successful', data: { firstname: 'MUSA', surname: 'IBRAHIM' }, nin_data: {} });
    const result = await provider().check(request('NIN', '12345678901'));
    expect(result.outcome).toBe(IdCheckStatus.MISMATCH);
    expect(result.name).toBe('MUSA IBRAHIM');
  });

  it('separates "no such number" from "we could not check"', async () => {
    stubFetch({ status: false, detail: 'No record found for this NIN' });
    expect((await provider().check(request('NIN', '12345678901'))).outcome).toBe(IdCheckStatus.NOT_FOUND);

    stubFetch({ status: false, detail: 'Service temporarily unavailable' });
    expect((await provider().check(request('NIN', '12345678901'))).outcome).toBe(IdCheckStatus.ERROR);
  });

  it('calls bad credentials and an empty wallet an error, not a verdict on the ID', async () => {
    // The exact envelope api.prembly.com returns for a rejected key.
    stubFetch(
      {
        status: false,
        message: 'Invalid API key or inactive organisation.',
        data: null,
        errors: { code: 'authentication_failed' },
        meta: { timestamp: '2026-09-28T08:23:15.601111', version: 'v1' },
      },
      401,
    );
    const rejected = await provider().check(request('NIN', '12345678901'));
    expect(rejected.outcome).toBe(IdCheckStatus.ERROR);
    expect(rejected.detail).toContain('rejected our credentials');

    // The same, but answered under HTTP 200 — it's still our account's
    // problem, never a verdict on the person's ID.
    stubFetch({ status: false, message: 'Invalid API key or inactive organisation.', data: null });
    expect((await provider().check(request('NIN', '12345678901'))).outcome).toBe(IdCheckStatus.ERROR);

    stubFetch({ status: false, detail: 'Insufficient wallet balance' });
    expect((await provider().check(request('NIN', '12345678901'))).outcome).toBe(IdCheckStatus.ERROR);
  });

  it('is not fooled by an empty payload object', async () => {
    stubFetch({ status: true, detail: 'Verification Successful', data: {}, nin_data: {} });
    expect((await provider().check(request('NIN', '12345678901'))).outcome).toBe(IdCheckStatus.ERROR);
  });

  it('never throws when the service is unreachable', async () => {
    global.fetch = (async () => {
      throw new Error('socket hang up');
    }) as unknown as typeof fetch;
    const result = await provider().check(request('NIN', '12345678901'));
    expect(result.outcome).toBe(IdCheckStatus.ERROR);
    expect(result.detail).toContain('could not be reached');
  });

  it('does not spend a lookup it cannot make or judge', async () => {
    stubFetch({ status: true, detail: 'ok', data: { firstname: 'Chinedu', surname: 'Okonkwo' } });
    const noName = await provider().check({ ...request('NIN', '12345678901'), subject: { firstName: null, lastName: null, fullName: null, dateOfBirth: null } });
    expect(noName.outcome).toBe(IdCheckStatus.UNSUPPORTED);
    expect(calls).toHaveLength(0);
  });
});

function request(idType: IdCheckRequest['idType'], idNumber: string): IdCheckRequest {
  return {
    idType,
    idNumber,
    subject: { firstName: 'Chinedu', lastName: 'Okonkwo', fullName: 'Chinedu Okonkwo', dateOfBirth: new Date('1995-04-17T00:00:00.000Z') },
  };
}
