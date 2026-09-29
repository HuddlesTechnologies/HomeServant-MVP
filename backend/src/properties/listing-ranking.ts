import { createHash } from 'crypto';

/// What the browse/search order needs to know about one listing.
export interface RankCandidate {
  id: string;
  createdAt: Date;
  /// Can a tenant book it right now? False for an occupied rental or a
  /// shortlet that's booked out at the moment.
  available: boolean;
  /// 0 none, 1 boosted, 2 top (admin ranking, already expiry-checked).
  adminBoost: number;
  /// A paid "Featured" ad is running.
  featured: boolean;
}

/// The browse/search order. The rules keep promotion from being an unfair
/// advantage:
///
/// 1. Available listings always come before unavailable ones. A promoted
///    shortlet that's booked out drops below every bookable listing, so
///    tenants never see a wall of "currently unavailable" at the top.
/// 2. Among available listings, promoted ones (admin-ranked or featured)
///    only fill one slot in every [slotEvery] — positions 0, slotEvery,
///    2·slotEvery… — and every other slot goes to ordinary listings, newest
///    first. Promoted listings left over when ordinary ones run out follow.
/// 3. Promoted listings are ordered by strength (top > boosted/featured),
///    and listings of equal strength rotate every day ([day]) so the same
///    one isn't always first.
/// 4. Unavailable listings follow, newest first, with no promotion.
export function rankListings(candidates: RankCandidate[], slotEvery: number, day: string): string[] {
  const strength = (c: RankCandidate) => Math.max(c.adminBoost, c.featured ? 1 : 0);
  const newestFirst = (a: RankCandidate, b: RankCandidate) => b.createdAt.getTime() - a.createdAt.getTime();
  const rotation = (c: RankCandidate) => createHash('sha1').update(`${day}:${c.id}`).digest('hex');

  const available = candidates.filter((c) => c.available);
  const promoted = available
    .filter((c) => strength(c) > 0)
    .sort((a, b) => strength(b) - strength(a) || rotation(a).localeCompare(rotation(b)));
  const organic = available.filter((c) => strength(c) === 0).sort(newestFirst);
  const unavailable = candidates.filter((c) => !c.available).sort(newestFirst);

  const every = Math.max(2, slotEvery);
  const ordered: string[] = [];
  let p = 0;
  let o = 0;
  while (p < promoted.length || o < organic.length) {
    const promotedSlot = ordered.length % every === 0;
    if ((promotedSlot && p < promoted.length) || o >= organic.length) {
      ordered.push(promoted[p++].id);
    } else {
      ordered.push(organic[o++].id);
    }
  }
  return [...ordered, ...unavailable.map((c) => c.id)];
}
