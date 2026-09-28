/// Comparing the name an issuing authority holds against the name on the
/// account. This is the whole basis for verifying someone without a human
/// looking at their documents, so the rule is deliberately conservative:
/// a loose match hands a stranger a verified badge (and, for a landlord,
/// eventually payouts), while a strict one costs nothing worse than a
/// moderator glancing at a submission that would have passed.
///
/// The rule: names are compared as unordered sets of tokens, because
/// Nigerian names are written surname-first about as often as
/// surname-last, and the authority's own field order can't be relied on
/// either. Two tokens must agree (one, if either side only has one) —
/// enough to survive a missing or different middle name, not enough for
/// two relatives who share a surname to pass for each other.

/// Honorifics and prefixes people put in a name field but registries
/// don't, and which must not count towards a match.
const TITLES = new Set([
  'mr',
  'mrs',
  'miss',
  'ms',
  'mister',
  'master',
  'dr',
  'doctor',
  'prof',
  'professor',
  'engr',
  'engineer',
  'arc',
  'barr',
  'barrister',
  'chief',
  'alhaji',
  'alhaja',
  'hajia',
  'pastor',
  'rev',
  'reverend',
  'evang',
  'bishop',
  'imam',
  'hon',
  'honourable',
  'sir',
  'madam',
  'late',
]);

/// Lower-cases, strips accents and punctuation, drops honorifics, and
/// drops single letters (a middle initial can't confirm or deny anything).
export function nameTokens(value: string | null | undefined): string[] {
  if (!value) return [];
  return value
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z\s]/g, ' ')
    .split(/\s+/)
    .filter((token) => token.length > 1 && !TITLES.has(token));
}

/// Edit distance, capped: we only ever ask "is this 0 or 1 edits away",
/// so there's no need for the full matrix.
function withinOneEdit(a: string, b: string): boolean {
  if (a === b) return true;
  if (Math.abs(a.length - b.length) > 1) return false;
  const [shorter, longer] = a.length <= b.length ? [a, b] : [b, a];
  let i = 0;
  let j = 0;
  let edits = 0;
  while (i < shorter.length && j < longer.length) {
    if (shorter[i] === longer[j]) {
      i++;
      j++;
      continue;
    }
    if (++edits > 1) return false;
    if (shorter.length === longer.length) i++;
    j++;
  }
  return edits + (longer.length - j) + (shorter.length - i) <= 1;
}

/// A single typo in a long name is tolerated ("Chukwuemeka" vs
/// "Chukwuemeke"); short names must be exact, since one edit on a
/// four-letter name can turn it into a different name entirely
/// ("Femi"/"Remi", "Bola"/"Tola").
function tokensAgree(a: string, b: string): boolean {
  if (a === b) return true;
  return a.length >= 6 && b.length >= 6 && withinOneEdit(a, b);
}

export interface NameComparison {
  matched: boolean;
  /// How many of the account's name parts the authority's name also has.
  shared: number;
  /// How many had to agree for this to be a match.
  required: number;
  /// One line for a reviewer, and for the note on an automatic rejection.
  reason: string;
}

/// [authorityName] is what the registry returned; [accountName] is what's
/// on the HomeServant account.
export function compareNames(authorityName: string | null | undefined, accountName: string | null | undefined): NameComparison {
  const authority = nameTokens(authorityName);
  const account = nameTokens(accountName);
  if (authority.length === 0 || account.length === 0) {
    return { matched: false, shared: 0, required: 1, reason: 'There was no name to compare on one side' };
  }

  const unmatchedAuthority = [...authority];
  let shared = 0;
  for (const token of account) {
    const at = unmatchedAuthority.findIndex((candidate) => tokensAgree(token, candidate));
    if (at === -1) continue;
    // Each authority token can only be spent once, so a name repeated on
    // the account ("Bello Bello") can't match a single "Bello".
    unmatchedAuthority.splice(at, 1);
    shared++;
  }

  const required = Math.min(2, authority.length, account.length);
  const matched = shared >= required;
  return {
    matched,
    shared,
    required,
    reason: matched
      ? `${shared} of ${account.length} name parts match the name on record`
      : `Only ${shared} name part${shared === 1 ? '' : 's'} match the name on record (${required} needed)`,
  };
}

/// The single best name to compare against a registry: the full name when
/// it has more than one part (signup's own field, and the most complete),
/// otherwise the first/last pair. Deliberately NOT all three concatenated
/// — repeated tokens would let one matching name part be counted twice.
export function subjectDisplayName(subject: { firstName: string | null; lastName: string | null; fullName: string | null }): string | null {
  if (nameTokens(subject.fullName).length >= 2) return subject.fullName;
  const pair = [subject.firstName, subject.lastName].filter((part) => !!part?.trim()).join(' ');
  return pair || subject.fullName || null;
}
