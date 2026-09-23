import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../models/dashboard_theme.dart';
import '../state/app_state.dart';

/// Bottom sheet that shows the tenant's referral code so they can invite
/// friends. There's no share-sheet package in this project yet, so
/// "sharing" copies a ready-made invite message to the clipboard instead —
/// the user can paste it into WhatsApp, SMS, etc.
Future<void> showInviteFriendsSheet(BuildContext context, {required DashboardTheme theme}) async {
  final appState = context.read<AppState>();
  // Normally already populated (the server assigns a code the moment it's
  // first needed, and every profile fetch/update carries it back) — this
  // is just a fallback for the rare case a session hasn't fetched it yet.
  if (appState.myReferralCode.isEmpty) {
    await appState.refreshProfile();
  }
  final code = appState.myReferralCode;
  if (!context.mounted) return;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => _InviteFriendsSheet(code: code),
  );
}

class _InviteFriendsSheet extends StatelessWidget {
  const _InviteFriendsSheet({required this.code});

  final String code;

  String get _message =>
      'Join me on Home Servant to find your next home! Use my invite code $code when you sign up.';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_add_alt_rounded, color: AppColors.navy, size: 22),
                const SizedBox(width: 10),
                Text('Invite Friends', style: AppTextStyles.heading(color: AppColors.navy, size: 20)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Share your code — friends who sign up with it help you both unlock rewards.',
              style: AppTextStyles.body(color: AppColors.hintGrey, size: 14),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.sand.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.navy.withValues(alpha: 0.12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      code,
                      style: AppTextStyles.heading(color: AppColors.navy, size: 22),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('Referral code copied')));
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.copy_rounded, color: AppColors.navy, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _message));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Invite message copied — paste it anywhere')));
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.ios_share_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text('Copy Invite Message', style: AppTextStyles.button(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
