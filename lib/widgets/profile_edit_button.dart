import 'package:flutter/material.dart';
import '../core/theme/app_text_styles.dart';

/// The outlined "Edit Profile" pill shown at the top of every profile
/// screen (tenant, vendor, landlord) — each used to define its own
/// private, near-identical `_EditProfileButton`.
class ProfileEditButton extends StatelessWidget {
  const ProfileEditButton({super.key, required this.color, required this.onTap, this.compact = false});

  /// Border/icon/text colour — every profile screen draws this directly on
  /// its own background rather than through a surface, so a single colour
  /// (the caller's theme accent, or a fixed brand colour) is enough.
  final Color color;
  final VoidCallback onTap;

  /// The vendor Shop Profile screen uses a visibly smaller pill (tighter
  /// padding, smaller icon/text) than the tenant/landlord ones — kept as an
  /// explicit size variant rather than silently drifting them together.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 14.0 : 16.0;
    final fontSize = compact ? 12.5 : 14.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18, vertical: compact ? 8 : 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_outlined, color: color, size: iconSize),
            SizedBox(width: compact ? 6 : 8),
            Text('Edit Profile', style: AppTextStyles.body(color: color, weight: FontWeight.w700, size: fontSize)),
          ],
        ),
      ),
    );
  }
}
