import { Logger } from '@nestjs/common';
import { IdCheckStatus, IdType } from '@prisma/client';
import { IdCheckProvider, IdCheckRequest, IdCheckResult, idCheckResult } from './id-check-provider.interface';
import { compareNames, nameTokens, subjectDisplayName } from './name-match';

/// Prembly (Identitypass) — looks an ID number up with the body that issued
/// it (NIMC for a NIN, the FRSC for a driver's licence, INEC for a voter's
/// card, Immigration for a passport) and returns the name held against it.
///
/// Auth is the `x-api-key` header alone. `app-id` belonged to their older
/// platform; it is still sent when PREMBLY_APP_ID is set, because their
/// legacy hosts require it and the current API ignores it.
///
/// WHAT IS AND ISN'T CONFIRMED (measured 2026-09-28, against a real key):
///
///   * `https://api.prembly.com` is the live host and answers with a
///     structured envelope (`{status, message, detail, data, billing_info,
///     verification, meta}`). The older `api.myidentitypass.com` /
///     `sandbox.myidentitypass.com` hosts complete a TLS handshake and then
///     drop the connection without replying — both from curl and from
///     Node's fetch — so this no longer targets them.
///   * `x-api-key` is definitely the auth header: omitting it gives
///     "Authentication credentials were not provided", while a rejected key
///     gives "Invalid API key or inactive organisation".
///   * The per-type paths and per-type success payloads below are NOT
///     confirmed against the live API. Every path under
///     `/identitypass/verification/` returns 401 before routing resolves
///     (a made-up name answers exactly like a real one), so endpoint names
///     cannot be probed without credentials that authenticate. They follow
///     Prembly's docs, whose own pages disagree with each other about host,
///     version and payload key. Once a working key exists, confirm each
///     [ENDPOINTS] entry and the name each one returns.
///
/// Responses also carry base64 photo and signature data, and billing
/// information. None of it is logged or returned — only the outcome, the
/// name, and the provider's own one-line message.
const DEFAULT_BASE_URL = 'https://api.prembly.com/identitypass';

const REQUEST_TIMEOUT_MS = 20_000;

interface EndpointSpec {
  path: string;
  /// Request body, minus the ID number itself.
  extraFields(request: IdCheckRequest): Record<string, string>;
  /// The field holding the ID number for this endpoint.
  numberField(idNumber: string): Record<string, string>;
  /// Anything the account must have before the lookup is worth making.
  requires?(request: IdCheckRequest): string | null;
}

/// Every spelling of a name field seen across their endpoints and
/// countries. Deliberately tolerant: their payload keys differ per ID type
/// (`firstname`/`surname` on a NIN, `firstName`/`lastName` on a licence,
/// `first_name`/`last_name` on a passport, a single `fullName` on a voter's
/// card, `identity_name` on some countries), and a reader that only knew
/// one spelling would call a perfectly good answer unreadable.
const GIVEN_NAME_KEYS = ['firstname', 'first_name', 'firstName', 'given_name', 'givenName'];
const MIDDLE_NAME_KEYS = ['middlename', 'middle_name', 'middleName'];
const SURNAME_KEYS = ['surname', 'lastname', 'last_name', 'lastName', 'family_name'];
const WHOLE_NAME_KEYS = ['identity_name', 'fullName', 'full_name', 'name'];

function text(data: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = data[key];
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return null;
}

/// The name held on record, however this particular endpoint spells it.
function readName(data: Record<string, unknown>): string | null {
  const whole = text(data, WHOLE_NAME_KEYS);
  if (whole) return whole;
  const parts = [text(data, GIVEN_NAME_KEYS), text(data, MIDDLE_NAME_KEYS), text(data, SURNAME_KEYS)].filter((part) => !!part);
  return parts.length > 0 ? parts.join(' ') : null;
}

/// The surname to send where an endpoint asks for one. Nigerian full names
/// are written surname-first about as often as surname-last, so when
/// there's no explicit [lastName] this guesses the last token — a wrong
/// guess costs a NOT_FOUND and a manual review, never a false match (the
/// name that comes back is still compared in full).
function surnameFor(request: IdCheckRequest): string | null {
  const explicit = request.subject.lastName?.trim();
  if (explicit) return explicit;
  const tokens = nameTokens(request.subject.fullName);
  return tokens.length > 0 ? tokens[tokens.length - 1] : null;
}

function firstNameFor(request: IdCheckRequest): string | null {
  const explicit = request.subject.firstName?.trim();
  if (explicit) return explicit;
  const tokens = nameTokens(request.subject.fullName);
  return tokens.length > 0 ? tokens[0] : null;
}

function dobFor(request: IdCheckRequest): string | null {
  const dob = request.subject.dateOfBirth;
  return dob ? dob.toISOString().slice(0, 10) : null;
}

function optional(fields: Record<string, string | null>): Record<string, string> {
  return Object.fromEntries(Object.entries(fields).filter((entry): entry is [string, string] => !!entry[1]));
}

const ENDPOINTS: Record<IdType, EndpointSpec> = {
  /// NIMC lookup. An 11-digit NIN goes in `number_nin`; a 16-character
  /// virtual NIN would go in `number`. The app's own format rule only
  /// allows the former, but both are handled so a later change to that
  /// rule doesn't silently break the lookup.
  NIN: {
    path: '/verification/vnin',
    numberField: (idNumber) => (/^\d{11}$/.test(idNumber) ? { number_nin: idNumber } : { number: idNumber }) as Record<string, string>,
    extraFields: () => ({}),
  },
  DRIVERS_LICENSE: {
    path: '/verification/drivers_license',
    numberField: (idNumber) => ({ number: idNumber }),
    extraFields: (request) => optional({ dob: dobFor(request) }),
  },
  VOTERS_CARD: {
    path: '/verification/voters_card',
    numberField: (idNumber) => ({ number: idNumber }),
    /// INEC's lookup also takes `state` and `lga`, which this app never
    /// asks anyone for; they're left out and the VIN plus name carries the
    /// lookup. If Prembly requires them, the result is an ERROR and a
    /// manual review, not a wrong decision.
    extraFields: (request) => optional({ last_name: surnameFor(request), first_name: firstNameFor(request), dob: dobFor(request) }),
  },
  INTERNATIONAL_PASSPORT: {
    path: '/verification/national_passport',
    numberField: (idNumber) => ({ number: idNumber }),
    extraFields: (request) => optional({ last_name: surnameFor(request) }),
    requires: (request) => (surnameFor(request) ? null : 'A passport lookup needs a surname, and this account has no name on it yet.'),
  },
};

/// Phrases they answer with when the registry simply has no such number —
/// a real answer about the ID, not a failure of ours.
const NOT_FOUND_PATTERNS = [/not\s*found/i, /no\s*record/i, /does\s*not\s*exist/i, /unable to (find|retrieve)/i, /invalid\s*(nin|number|id|vin|license|licence|passport)/i];

/// Phrases that mean our own account is the problem, not the ID.
const CREDENTIAL_PATTERNS = [/invalid api key/i, /inactive organisation/i, /inactive organization/i, /authentication credentials/i, /token not valid/i];

interface PremblyEnvelope {
  status?: boolean;
  detail?: string;
  message?: string;
  response_code?: string;
  verification?: { status?: string; reference?: string };
  [key: string]: unknown;
}

export class PremblyIdCheckProvider implements IdCheckProvider {
  readonly name = 'prembly';
  private readonly logger = new Logger('IdCheck');

  constructor(
    private readonly apiKey: string,
    private readonly appId: string | null = null,
    private readonly baseUrl: string = DEFAULT_BASE_URL,
  ) {}

  async check(request: IdCheckRequest): Promise<IdCheckResult> {
    const spec = ENDPOINTS[request.idType];
    const missing = spec.requires?.(request);
    if (missing) return idCheckResult(this.name, IdCheckStatus.UNSUPPORTED, missing);

    const accountName = subjectDisplayName(request.subject);
    if (!accountName) {
      return idCheckResult(this.name, IdCheckStatus.UNSUPPORTED, 'This account has no name yet, so there is nothing to check the ID against.');
    }

    let envelope: PremblyEnvelope;
    let httpStatus: number;
    try {
      const response = await fetch(`${this.baseUrl.replace(/\/+$/, '')}${spec.path}`, {
        method: 'POST',
        headers: {
          'x-api-key': this.apiKey,
          // Their legacy hosts require this; the current API ignores it.
          ...(this.appId ? { 'app-id': this.appId } : {}),
          'content-type': 'application/json',
          accept: 'application/json',
        },
        body: JSON.stringify({ ...spec.numberField(request.idNumber), ...spec.extraFields(request) }),
        signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      });
      httpStatus = response.status;
      envelope = (await response.json()) as PremblyEnvelope;
    } catch (error) {
      // Down, slow, or answering with something that isn't JSON. Never
      // surfaced to the person signing up; a moderator picks it up.
      this.logger.warn(`Prembly ${request.idType} lookup failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      return idCheckResult(this.name, IdCheckStatus.ERROR, 'The ID check service could not be reached. This needs a manual review, or run the check again.');
    }

    const detail = (envelope.detail ?? envelope.message ?? '').trim();
    const reference = envelope.verification?.reference ?? null;

    // Our account, not their ID. Loud, because every check fails until
    // somebody fixes it, and each one silently lands in the review queue.
    if (httpStatus === 401 || httpStatus === 403 || CREDENTIAL_PATTERNS.some((pattern) => pattern.test(detail))) {
      this.logger.error(`Prembly rejected our credentials (HTTP ${httpStatus}): ${detail || 'no detail'} — check PREMBLY_X_API_KEY and that the Prembly organisation is active`);
      return idCheckResult(this.name, IdCheckStatus.ERROR, 'The ID check service rejected our credentials. Needs a manual review.', { reference });
    }
    if (httpStatus === 402 || /insufficient|wallet|balance|credit/i.test(detail)) {
      this.logger.error(`Prembly refused the ${request.idType} lookup for billing reasons: ${detail}`);
      return idCheckResult(this.name, IdCheckStatus.ERROR, 'The ID check service refused the lookup (billing). Needs a manual review.', { reference });
    }

    const data = this.readData(envelope);
    const authorityName = data ? readName(data) : null;

    if (envelope.status !== true || !authorityName) {
      const notFound = NOT_FOUND_PATTERNS.some((pattern) => pattern.test(detail));
      if (notFound) {
        return idCheckResult(this.name, IdCheckStatus.NOT_FOUND, detail || 'No record of this ID number was found.', { reference });
      }
      this.logger.warn(`Prembly ${request.idType} lookup unusable (HTTP ${httpStatus}, status ${String(envelope.status)}): ${detail || 'no detail'}`);
      return idCheckResult(this.name, IdCheckStatus.ERROR, detail ? `The ID check service answered: ${detail}` : 'The ID check service gave an answer we could not read.', {
        reference,
      });
    }

    const comparison = compareNames(authorityName, accountName);
    return idCheckResult(this.name, comparison.matched ? IdCheckStatus.MATCH : IdCheckStatus.MISMATCH, comparison.reason, {
      reference,
      name: authorityName,
    });
  }

  /// Finds the payload. The current API puts it under `data`; their older
  /// endpoints used `nin_data`, `frsc_data` or `vc_data`, and the current
  /// NIN response carries an EMPTY `nin_data: {}` alongside the real
  /// `data` — so an empty object must never be mistaken for the payload.
  private readData(envelope: PremblyEnvelope): Record<string, unknown> | null {
    const candidates = ['data', ...Object.keys(envelope).filter((key) => key.endsWith('_data'))];
    for (const key of candidates) {
      const value = envelope[key];
      if (!value || typeof value !== 'object' || Array.isArray(value)) continue;
      const record = value as Record<string, unknown>;
      if (Object.keys(record).length === 0) continue;
      return record;
    }
    return null;
  }
}
