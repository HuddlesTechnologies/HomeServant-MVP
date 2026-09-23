import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import '../../widgets/profile_edit_button.dart';
import '../../widgets/profile_menu_tile.dart';
import '../../widgets/support_sheet.dart';
import '../../widgets/theme_picker_sheet.dart';
import '../../widgets/upload_picker.dart';
import '../dashboard/edit_profile_screen.dart';
import '../dashboard/notifications_screen.dart';
import 'landlord_add_property_screen.dart';
import 'landlord_bank_details_screen.dart';

/// Profile Settings tab of the redesigned landlord dashboard — a fixed
/// dark-navy screen (independent of the switchable [DashboardTheme], which
/// this same screen exposes via the "Theme" row) matching the new mockup.
class LandlordProfileScreen extends StatelessWidget {
  const LandlordProfileScreen({super.key, required this.onLogOut, this.onOverview});

  final VoidCallback onLogOut;

  /// Jumps back to the Home tab — wired by the parent dashboard, since this
  /// screen is one tab among several rather than a standalone route.
  final VoidCallback? onOverview;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final photoPath = appState.profilePhotoPath;
    final theme = appState.dashboardTheme;

    return Container(
      color: AppColors.navy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, color: AppColors.gold, size: 20),
              const SizedBox(width: 10),
              Text('Profile Settings', style: AppTextStyles.heading(color: AppColors.gold, size: 19)),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.4),
              // Biased toward the top rather than dead-center — a plain
              // center-crop on an uncropped photo (there's no crop step at
              // pick time) tends to zoom in on the nose/mouth instead of
              // showing the whole face.
              image: photoPath != null
                  ? DecorationImage(image: imageProviderForPath(photoPath), fit: BoxFit.cover, alignment: const Alignment(0, -0.3))
                  : null,
            ),
            child: photoPath == null ? const Icon(Icons.person_outline, color: Colors.white, size: 40) : null,
          ),
          const SizedBox(height: 16),
          ProfileEditButton(
            color: AppColors.gold,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
          ProfileMenuTile(
            icon: Icons.remove_red_eye_outlined,
            label: 'Overview',
            iconColor: AppColors.gold,
            badgeColor: Colors.white.withValues(alpha: 0.08),
            labelColor: Colors.white,
            dividerColor: Colors.white.withValues(alpha: 0.15),
            onTap: onOverview ?? () {},
          ),
          ProfileMenuTile(
            icon: Icons.add_circle_outline_rounded,
            label: 'Add Property',
            iconColor: AppColors.gold,
            badgeColor: Colors.white.withValues(alpha: 0.08),
            labelColor: Colors.white,
            dividerColor: Colors.white.withValues(alpha: 0.15),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LandlordAddPropertyScreen()),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.account_balance_rounded,
            label: 'Bank Details',
            iconColor: AppColors.gold,
            badgeColor: Colors.white.withValues(alpha: 0.08),
            labelColor: Colors.white,
            dividerColor: Colors.white.withValues(alpha: 0.15),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LandlordBankDetailsScreen()),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.remove_red_eye_outlined,
            label: 'Theme',
            iconColor: AppColors.gold,
            badgeColor: Colors.white.withValues(alpha: 0.08),
            labelColor: Colors.white,
            dividerColor: Colors.white.withValues(alpha: 0.15),
            onTap: () async {
              final picked = await showThemePickerSheet(context, current: theme);
              if (picked != null && context.mounted) {
                context.read<AppState>().setDashboardTheme(picked);
              }
            },
          ),
          ProfileMenuTile(
            icon: Icons.error_outline_rounded,
            label: 'Alert',
            iconColor: AppColors.gold,
            badgeColor: Colors.white.withValues(alpha: 0.08),
            labelColor: Colors.white,
            dividerColor: Colors.white.withValues(alpha: 0.15),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => NotificationsScreen(theme: theme)),
            ),
          ),
          ProfileMenuTile(
            icon: Icons.support_agent_rounded,
            label: 'Support',
            iconColor: AppColors.gold,
            badgeColor: Colors.white.withValues(alpha: 0.08),
            labelColor: Colors.white,
            dividerColor: Colors.white.withValues(alpha: 0.15),
            onTap: () => showSupportOptionsSheet(context, theme: theme),
          ),
          ProfileMenuTile(
            icon: Icons.logout_rounded,
            label: 'Log Out',
            iconColor: AppColors.gold,
            badgeColor: Colors.white.withValues(alpha: 0.08),
            labelColor: Colors.white,
            dividerColor: Colors.white.withValues(alpha: 0.15),
            onTap: onLogOut,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}
