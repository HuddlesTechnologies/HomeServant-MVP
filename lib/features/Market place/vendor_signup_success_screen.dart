import 'package:flutter/material.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../widgets/pill_button.dart';
import 'vendor_dashboard_screen.dart';

/// Shown once a vendor's shop is created. There's no application-review
/// workflow — the shop is live immediately (see backend/README.md's
/// "Not built yet" for why), so this confirms that rather than implying a
/// wait that doesn't happen.
class VendorSignupSuccessScreen extends StatelessWidget {
  const VendorSignupSuccessScreen({super.key, required this.theme, required this.businessName});

  final DashboardTheme theme;
  final String businessName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Center(
          child: ResponsiveCenter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(color: theme.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(Icons.check_circle_rounded, color: theme.accent, size: 48),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    "You're all set, $businessName!",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heading(color: theme.foreground, size: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your shop is live. Head to your dashboard to start listing products.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.65), size: 14.5),
                  ),
                  const SizedBox(height: 36),
                  PillButton(
                    label: 'Go to My Shop',
                    backgroundColor: theme.accent,
                    textColor: theme.onAccent,
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => VendorDashboardScreen(theme: theme)),
                      (route) => false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
