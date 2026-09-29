import 'package:flutter/material.dart';
import '../api/models/verification.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// The verification blue, used only for the check icon (never text): about
/// 4.7:1 on white, 3.3:1 on navy and 3.1:1 on landlord sand (icons need
/// 3:1). Any label uses the caller's own text colour.
const verifiedBlue = Color(0xFF1D72D8);

/// A check mark plus an optional label, e.g. next to a name. [textColor]
/// must contrast with whatever this sits on.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, required this.textColor, this.label = 'Verified', this.size = 12.5});

  final Color textColor;

  /// Null for the icon alone.
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.verified_rounded, color: verifiedBlue, size: size + 4);
    final text = label;
    if (text == null) return Tooltip(message: 'Verified by HomeServant', child: icon);
    return Tooltip(
      message: 'Identity verified by HomeServant',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 4),
          Text(text, style: AppTextStyles.body(color: textColor, size: size, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// A user's own verification state on their profile: Verified, awaiting
/// review, or rejected with what to fix. White card, navy text.
class VerificationStatusCard extends StatelessWidget {
  const VerificationStatusCard({super.key, required this.status, this.note, this.listingsHidden = false, this.onGetVerified});

  final VerificationStatus? status;
  final String? note;

  /// Landlord whose listings Platform Controls is hiding until verified.
  final bool listingsHidden;

  /// Shows a "Get verified" / "Resubmit" button when set.
  final VoidCallback? onGetVerified;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color iconColor, String title, String? body) = switch (status) {
      VerificationStatus.approved => (Icons.verified_rounded, verifiedBlue, 'Identity verified', null),
      VerificationStatus.pending => (
        Icons.hourglass_top_rounded,
        const Color(0xFFB7791F),
        'Verification in review',
        'HomeServant is checking your ID. You will be notified when it is done.',
      ),
      VerificationStatus.rejected => (
        Icons.error_outline_rounded,
        const Color(0xFFC53030),
        'Verification needs attention',
        note == null ? 'Please contact support to update your documents.' : 'What to fix: $note',
      ),
      _ => (
        Icons.shield_outlined,
        AppColors.hintGrey,
        'Not verified',
        'Your identity documents have not been submitted yet.',
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700)),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(body, style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 12.5)),
                ],
                if (listingsHidden) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Your listings are hidden from tenants until your identity is verified.',
                    style: AppTextStyles.body(color: const Color(0xFFA61B1B), size: 12.5, weight: FontWeight.w600),
                  ),
                ],
                if (onGetVerified != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                      onPressed: onGetVerified,
                      child: Text(
                        status == VerificationStatus.rejected ? 'Resubmit documents' : 'Get verified',
                        style: AppTextStyles.body(color: Colors.white, size: 13, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
