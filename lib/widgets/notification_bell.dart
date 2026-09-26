import 'package:flutter/material.dart';

/// The "notifications" bell-with-unread-dot icon repeated in every
/// dashboard header (tenant, landlord Home, landlord Bookings) — each used
/// to hand-roll its own `Stack` + `Positioned` red dot.
///
/// Covers both the plain-dot presentation those three shared exactly
/// ([showDot], the default) and a numeric unread-count badge ([count]) for
/// callers — like the admin console — where a bare dot can't convey "how
/// many". [count] takes priority when both are provided.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.color, this.onTap, this.showDot = true, this.count});

  final Color color;
  final VoidCallback? onTap;

  /// Whether the unread dot is shown — callers that track read/unread
  /// state (like the tenant dashboard) pass this through; callers with no
  /// such state just leave it at the default. Ignored when [count] is set.
  final bool showDot;

  /// Unread count to render as a numeral instead of a plain dot; null or
  /// <= 0 shows nothing.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final resolvedCount = count;
    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.notifications_none_rounded, color: color),
        if (resolvedCount != null && resolvedCount > 0)
          Positioned(
            top: -4,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              child: Text(
                resolvedCount > 99 ? '99+' : '$resolvedCount',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
              ),
            ),
          )
        else if (resolvedCount == null && showDot)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
          ),
      ],
    );
    if (onTap == null) return icon;
    return InkWell(customBorder: const CircleBorder(), onTap: onTap, child: icon);
  }
}
