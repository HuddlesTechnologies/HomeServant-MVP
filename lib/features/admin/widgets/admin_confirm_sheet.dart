import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Shared destructive-action confirmation sheet for the admin console —
/// deactivate/delete a user, reject a vendor, remove a listing, etc.
Future<bool?> showAdminConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  bool destructive = true,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
            const SizedBox(height: 8),
            Text(body, style: AppTextStyles.body(color: AppColors.hintGrey, size: 14)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text('Cancel', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: destructive ? Colors.redAccent : AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text(actionLabel, style: AppTextStyles.button(color: Colors.white, size: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
