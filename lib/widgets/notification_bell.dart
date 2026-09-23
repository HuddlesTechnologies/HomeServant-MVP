import 'package:flutter/material.dart';

/// The "notifications" bell-with-unread-dot icon repeated in every
/// dashboard header (tenant, landlord Home, landlord Bookings) — each used
/// to hand-roll its own `Stack` + `Positioned` red dot.
///
/// Only covers the plain-dot presentation those three shared exactly; the
/// vendor dashboard's bell shows a numeric unread *count* badge instead of
/// a dot (via an `IconButton`, for its larger tap target), which is a
/// different enough shape that folding it in here would trade three real
/// duplicates for one widget with two visual modes — not a net win, so it
/// keeps its own implementation.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.color, this.onTap, this.showDot = true});

  final Color color;
  final VoidCallback? onTap;

  /// Whether the unread dot is shown — callers that track read/unread
  /// state (like the tenant dashboard) pass this through; callers with no
  /// such state just leave it at the default.
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.notifications_none_rounded, color: color),
        if (showDot)
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
