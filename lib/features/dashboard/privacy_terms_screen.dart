import 'package:flutter/material.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';

enum LegalDocumentKind { privacyPolicy, termsOfService }

const _privacySections = <(String, String)>[
  (
    'What we store',
    'Your profile details (name, email, phone, address), the theme you pick, your notification '
        'preferences, and the properties you save to your wishlist are kept for your account so the app '
        'works the way you set it up.',
  ),
  (
    "What we don't do",
    "Home Servant does not sell your data or share it with third parties. Property photos shown in "
        "this preview are sourced from Unsplash for demonstration purposes.",
  ),
  (
    'Your controls',
    'Optional Two-Factor Authentication and App Lock give you extra control over who can access your '
        'account and this app. You can deactivate or permanently delete your account at any time from '
        'Settings.',
  ),
];

const _termsSections = <(String, String)>[
  (
    'Using Home Servant',
    'Home Servant helps tenants discover rental listings and helps landlords manage properties. By '
        'using the app you agree to provide accurate information when listing or applying for a '
        'property.',
  ),
  (
    'Accounts',
    "You're responsible for keeping your login details and app-lock PIN secure. You can deactivate or "
        'permanently delete your account at any time from Settings.',
  ),
  (
    'Listings',
    'Property details are provided by landlords and are not independently verified by Home Servant. '
        'Always confirm details directly with the landlord before making a payment.',
  ),
];

class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.theme, required this.kind});

  final DashboardTheme theme;
  final LegalDocumentKind kind;

  @override
  Widget build(BuildContext context) {
    final isPrivacy = kind == LegalDocumentKind.privacyPolicy;
    final sections = isPrivacy ? _privacySections : _termsSections;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text(
          isPrivacy ? 'Privacy Policy' : 'Terms of Service',
          style: AppTextStyles.heading(color: theme.foreground, size: 18),
        ),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              for (final section in sections)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(section.$1, style: AppTextStyles.heading(color: theme.foreground, size: 15)),
                      const SizedBox(height: 6),
                      Text(
                        section.$2,
                        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.75), size: 13.5).copyWith(height: 1.5),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
