import 'package:flutter/material.dart';
import '../core/theme/app_text_styles.dart';
import '../models/dashboard_theme.dart';

/// The "nothing here yet" placeholder — a faded icon, a heading, and a
/// line of body copy, centred with 40px of horizontal breathing room.
///
/// History, Wishlist, Tenancy Agreements, and the Marketplace's Order
/// History screens each defined their own private copy of this exact
/// layout (same padding, same icon alpha, same type sizes), differing only
/// in icon and copy — this is that layout, parametrised.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.theme, required this.icon, required this.title, required this.message});

  final DashboardTheme theme;
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.foreground.withValues(alpha: 0.35), size: 56),
            const SizedBox(height: 16),
            Text(title, style: AppTextStyles.heading(color: theme.foreground, size: 18)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 14),
            ),
          ],
        ),
      ),
    );
  }
}
