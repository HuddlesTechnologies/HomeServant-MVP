/// The name a customer sees for a member of the support team: their first
/// name only (never their full name). Uses [firstName] when the account
/// has one and otherwise the first word of [fullName] — admins created
/// before first/last names were collected only have a full name.
export function adminPublicName(user: { firstName?: string | null; fullName?: string | null } | null | undefined): string | null {
  const first = user?.firstName?.trim();
  if (first) return first;
  const fromFull = user?.fullName?.trim().split(/\s+/)[0];
  return fromFull || null;
}

/// Builds a full name from first/last, falling back to [fullName] as sent.
export function joinName(firstName?: string | null, lastName?: string | null, fullName?: string | null): string {
  const joined = [firstName?.trim(), lastName?.trim()].filter((part) => !!part).join(' ');
  return joined || fullName?.trim() || '';
}
