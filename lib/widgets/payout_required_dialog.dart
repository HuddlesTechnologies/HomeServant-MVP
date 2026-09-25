import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'pill_button.dart';

/// Shown before a landlord/vendor submits a create-listing form (property
/// or marketplace product) when they don't have payout/bank details on
/// file yet — the server rejects that create call with a 400 either way
/// (see `PropertiesService`/`MarketplaceProductsService` payout gating),
/// so this is just the friendly client-side steer toward fixing it first
/// instead of letting the submit proceed to a guaranteed failure.
/// Resolves `true` if the person taps through to set up payout details.
Future<bool?> showPayoutRequiredDialog(
  BuildContext context, {
  String title = 'Set up payout details first',
  required String body,
  String actionLabel = 'Set Up Payout Details',
}) {
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
              child: const Icon(Icons.account_balance_rounded, color: AppColors.navy, size: 32),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.heading(color: AppColors.navy, size: 19)),
            const SizedBox(height: 10),
            Text(body, textAlign: TextAlign.center, style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.7), size: 14)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: actionLabel,
                backgroundColor: AppColors.navy,
                textColor: Colors.white,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not Now',
                style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.6), weight: FontWeight.w600, size: 13.5),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
