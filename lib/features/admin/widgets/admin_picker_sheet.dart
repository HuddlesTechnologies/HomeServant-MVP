import 'package:flutter/material.dart';
import '../../../api/models/admin_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Bottom sheet listing admin accounts to hand something off to — shared
/// by AdminReportsTab (transferring a report) and AdminMessagesTab
/// (transferring a chat thread), both of which populate [admins] from
/// `AdminRepository.findAdmins()`, the same list `AdminAdminsTab` already
/// fetches for its own admin roster. Styled to match
/// `showAdminConfirmSheet`/`showAdminReasonSheet` in `admin_confirm_sheet.dart`
/// rather than inventing a new sheet pattern.
Future<AdminAccount?> showAdminPickerSheet(
  BuildContext context, {
  required List<AdminAccount> admins,
  String title = 'Transfer to',
  Set<String> excludeAdminIds = const {},
}) {
  final candidates = excludeAdminIds.isEmpty ? admins : admins.where((a) => !excludeAdminIds.contains(a.id)).toList();
  return showModalBottomSheet<AdminAccount>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
            const SizedBox(height: 14),
            if (candidates.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No other admins available.',
                  style: AppTextStyles.body(color: AppColors.hintGrey, size: 13.5),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final admin = candidates[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        admin.fullName?.isNotEmpty == true ? admin.fullName! : admin.email,
                        style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 14),
                      ),
                      subtitle: Text(admin.email, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
                      trailing: Text(
                        admin.level.label,
                        style: AppTextStyles.body(color: AppColors.hintGrey, size: 12, weight: FontWeight.w600),
                      ),
                      onTap: () => Navigator.of(context).pop(admin),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
