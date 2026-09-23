import 'package:flutter/material.dart';
import '../core/theme/app_text_styles.dart';

/// One row of a profile screen's menu list: a circular icon badge, a
/// label, and an optional trailing divider. Tenant and landlord profile
/// screens each defined their own private, identical copy of this
/// (`_ProfileMenuTile`) — this is that widget, with every colour taken as
/// a parameter so each caller can still draw it on its own theme.
class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.iconColor,
    required this.badgeColor,
    required this.labelColor,
    required this.dividerColor,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Colour of [icon] itself.
  final Color iconColor;

  /// Fill colour of the circle behind [icon].
  final Color badgeColor;

  final Color labelColor;
  final Color dividerColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                  child: Icon(icon, color: iconColor, size: 19),
                ),
                const SizedBox(width: 16),
                Text(label, style: AppTextStyles.body(color: labelColor, size: 15.5, weight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        if (showDivider) Divider(color: dividerColor, height: 1),
      ],
    );
  }
}
