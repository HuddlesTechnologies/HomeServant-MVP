import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/responsive.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'pill_button.dart';

/// The full-bleed photo screen with the logo, a title, a subtitle and two
/// stacked buttons (navy on top, gold below) that Get Started and the
/// Login/Sign Up role pickers all share. They used to be three copies of
/// this layout differing only in their text.
class TwoChoiceScreen extends StatelessWidget {
  const TwoChoiceScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/homepage.jpg', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.navyDark.withValues(alpha: 0.3),
                  AppColors.navy.withValues(alpha: 0.2),
                  AppColors.navyDark.withValues(alpha: 0.35),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                if (Navigator.of(context).canPop())
                  Positioned(
                    top: 4,
                    left: 8,
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AppColors.white,
                        size: 20,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ResponsiveCenter(
                    child: Column(
                      children: [
                        const Spacer(flex: 2),
                        SvgPicture.asset('assets/icons/logo4.svg', width: 110),
                        const Spacer(flex: 2),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.heading(
                            color: AppColors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(
                            color: AppColors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(height: 28),
                        PillButton(
                          label: primaryLabel,
                          backgroundColor: AppColors.navy,
                          textColor: AppColors.white,
                          onPressed: onPrimary,
                        ),
                        const SizedBox(height: 14),
                        PillButton(
                          label: secondaryLabel,
                          backgroundColor: AppColors.gold,
                          textColor: AppColors.navy,
                          onPressed: onSecondary,
                        ),
                        const Spacer(flex: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
