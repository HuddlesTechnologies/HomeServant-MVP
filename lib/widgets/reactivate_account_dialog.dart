import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'pill_button.dart';

/// Shown when [AppState.login]/[AppState.loginWithGoogle] reports
/// `requiresReactivation` — the account is deactivated, and logging in
/// only actually proceeds once the person confirms they want it back.
/// Resolves `true` on confirm, `false`/`null` on cancel/dismiss.
Future<bool?> showReactivateAccountDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.restore_rounded, color: AppColors.navy, size: 32),
            ),
            const SizedBox(height: 20),
            Text(
              'Reactivate your account?',
              textAlign: TextAlign.center,
              style: AppTextStyles.heading(color: AppColors.navy, size: 19),
            ),
            const SizedBox(height: 10),
            Text(
              "This account was deactivated. Log in again to reactivate it — your profile and listings (if any) "
              "will be visible again right away.",
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.7), size: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: 'Reactivate & Log In',
                backgroundColor: AppColors.navy,
                textColor: Colors.white,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.6), weight: FontWeight.w600, size: 13.5),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
