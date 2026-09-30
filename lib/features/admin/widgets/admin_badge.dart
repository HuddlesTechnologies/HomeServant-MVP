import 'package:flutter/material.dart';
import '../../../core/theme/app_text_styles.dart';

enum AdminBadgeSize { small, regular, large }

/// A small tinted pill label ("Verified", "Suspended", "Support", ...)
/// in [color] on a 12%-alpha wash of the same color, in three sizes.
class AdminBadge extends StatelessWidget {
  const AdminBadge({super.key, required this.text, required this.color, this.size = AdminBadgeSize.regular});

  final String text;
  final Color color;
  final AdminBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final (hPad, vPad, radius, fontSize) = switch (size) {
      AdminBadgeSize.small => (6.0, 2.0, 8.0, 10.0),
      AdminBadgeSize.regular => (7.0, 2.0, 8.0, 10.5),
      AdminBadgeSize.large => (8.0, 3.0, 9.0, 11.0),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(radius)),
      child: Text(text, style: AppTextStyles.body(color: color, size: fontSize, weight: FontWeight.w700)),
    );
  }
}
