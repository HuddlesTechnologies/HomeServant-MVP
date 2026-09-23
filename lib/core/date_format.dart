/// Short month names, shared by every screen that formats a date as
/// "24 Oct 2026" or similar — History, Edit Profile, and the chat thread
/// screen each used to define their own identical `_months` list.
const monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Formats [date] as "24 Oct 2026" — the exact format History and Edit
/// Profile both need. The chat thread screen's timestamp format differs
/// (it adds a time-of-day), so it uses [monthAbbreviations] directly
/// rather than this.
String formatShortDate(DateTime date) => '${date.day} ${monthAbbreviations[date.month - 1]} ${date.year}';
