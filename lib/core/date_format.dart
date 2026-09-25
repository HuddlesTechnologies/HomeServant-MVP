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

/// "Good morning"/"Good afternoon"/"Good evening", based on the device's
/// local clock at call time — every dashboard greeting reads this instead
/// of a fixed string, so it actually reflects when someone opens the app
/// rather than always saying morning. Boundaries: before noon is morning,
/// noon up to 5pm is afternoon, otherwise evening.
String timeOfDayGreeting([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// "2m ago"/"3h ago"-style relative timestamp, falling back to
/// [formatShortDate] once [dt] is more than a week old — the shared
/// logic behind the near-identical formatters that used to be
/// duplicated in the chat thread, messages, and notifications screens.
String formatRelativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatShortDate(dt);
}
