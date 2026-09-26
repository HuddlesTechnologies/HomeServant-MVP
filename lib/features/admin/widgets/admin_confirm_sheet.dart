import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Result of [showAdminValueReasonSheet] — the typed value (new email/
/// password) alongside the required reason.
typedef AdminValueReason = ({String value, String reason});

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

/// Like [showAdminConfirmSheet] but requires typing a reason before the
/// action button enables — used wherever the affected user gets emailed
/// that reason verbatim (delisting a property/product), so there's
/// always something real to put in that email.
Future<String?> showAdminReasonSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  String hint = 'Reason (sent to the user by email)',
}) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              const SizedBox(height: 8),
              Text(body, style: AppTextStyles.body(color: AppColors.hintGrey, size: 14)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                maxLines: 3,
                onChanged: (_) => setSheetState(() {}),
                style: AppTextStyles.body(color: AppColors.navy, size: 14),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 14),
                  filled: true,
                  fillColor: AppColors.offWhite,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
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
                      onPressed: controller.text.trim().length >= 10
                          ? () => Navigator.of(context).pop(controller.text.trim())
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        // A disabled ElevatedButton otherwise falls back to
                        // Material 3's own near-white disabled background,
                        // but the label's white text is fixed regardless of
                        // state — invisible for as long as the button sits
                        // disabled, which is its starting state every time
                        // this sheet opens (before 10 characters are typed).
                        disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.35),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: Text(
                        actionLabel,
                        style: AppTextStyles.button(
                          color: Colors.white.withValues(alpha: controller.text.trim().length >= 10 ? 1 : 0.7),
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Like [showAdminReasonSheet] but also collects one extra value field
/// above the reason box (a new email address, or a new password) — used
/// by the admin-console user-security actions (change email, directly
/// set a password) that both need a value *and* a reason recorded for
/// the admin activity log. Submit stays disabled until both the value
/// passes [valueValidator] (if given) and the reason is at least 10
/// characters, same threshold as [showAdminReasonSheet].
Future<AdminValueReason?> showAdminValueReasonSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String actionLabel,
  required String valueLabel,
  String? valueHint,
  String? initialValue,
  bool obscureValue = false,
  String? Function(String)? valueValidator,
  String reasonHint = 'Reason (recorded in the admin activity log)',
}) {
  final valueController = TextEditingController(text: initialValue ?? '');
  final reasonController = TextEditingController();
  return showModalBottomSheet<AdminValueReason>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) {
        final valueError = valueValidator?.call(valueController.text.trim());
        final valueValid = valueController.text.trim().isNotEmpty && valueError == null;
        final reasonValid = reasonController.text.trim().length >= 10;
        final canSubmit = valueValid && reasonValid;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
                const SizedBox(height: 8),
                Text(body, style: AppTextStyles.body(color: AppColors.hintGrey, size: 14)),
                const SizedBox(height: 14),
                TextField(
                  controller: valueController,
                  obscureText: obscureValue,
                  onChanged: (_) => setSheetState(() {}),
                  style: AppTextStyles.body(color: AppColors.navy, size: 14),
                  decoration: InputDecoration(
                    labelText: valueLabel,
                    hintText: valueHint,
                    errorText: valueController.text.trim().isNotEmpty ? valueError : null,
                    labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                    hintStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 14),
                    filled: true,
                    fillColor: AppColors.offWhite,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  onChanged: (_) => setSheetState(() {}),
                  style: AppTextStyles.body(color: AppColors.navy, size: 14),
                  decoration: InputDecoration(
                    hintText: reasonHint,
                    hintStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 14),
                    filled: true,
                    fillColor: AppColors.offWhite,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
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
                        onPressed: canSubmit
                            ? () => Navigator.of(context).pop((value: valueController.text.trim(), reason: reasonController.text.trim()))
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          // See showAdminReasonSheet's identical comment —
                          // the disabled label needs an explicit color too,
                          // or it's invisible in this sheet's starting state.
                          disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.35),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                        child: Text(
                          actionLabel,
                          style: AppTextStyles.button(color: Colors.white.withValues(alpha: canSubmit ? 1 : 0.7), size: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
