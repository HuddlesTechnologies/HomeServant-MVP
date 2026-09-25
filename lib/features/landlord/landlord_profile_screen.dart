import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import '../../widgets/profile_menu_scaffold.dart';
import '../../widgets/support_sheet.dart';
import '../../widgets/theme_picker_sheet.dart';
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
    final badgeColor = Colors.white.withValues(alpha: 0.08);
    final dividerColor = Colors.white.withValues(alpha: 0.15);

    return ProfileMenuScaffold(
      backgroundColor: AppColors.navy,
      iconColor: AppColors.gold,
      labelColor: Colors.white,
      badgeColor: badgeColor,
      dividerColor: dividerColor,
      photoPath: photoPath,
      photoBorderColor: Colors.white,
      editButtonColor: AppColors.gold,
      onEditProfileTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
      header: Row(
        children: [
          const Icon(Icons.tune_rounded, color: AppColors.gold, size: 20),
          const SizedBox(width: 10),
          Text('Profile Settings', style: AppTextStyles.heading(color: AppColors.gold, size: 19)),
        ],
      ),
      items: [
        ProfileMenuItemSpec(
          icon: Icons.remove_red_eye_outlined,
          label: 'Overview',
          onTap: onOverview ?? () {},
        ),
        ProfileMenuItemSpec(
          icon: Icons.add_circle_outline_rounded,
          label: 'Add Property',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LandlordAddPropertyScreen()),
          ),
        ),
        ProfileMenuItemSpec(
          icon: Icons.account_balance_rounded,
          label: 'Bank Details',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LandlordBankDetailsScreen()),
          ),
        ),
        ProfileMenuItemSpec(
          icon: Icons.remove_red_eye_outlined,
          label: 'Theme',
          onTap: () async {
            final picked = await showThemePickerSheet(context, current: theme);
            if (picked != null && context.mounted) {
              context.read<AppState>().setDashboardTheme(picked);
            }
          },
        ),
        ProfileMenuItemSpec(
          icon: Icons.error_outline_rounded,
          label: 'Alert',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => NotificationsScreen(theme: theme)),
          ),
        ),
        ProfileMenuItemSpec(
          icon: Icons.support_agent_rounded,
          label: 'Support',
          onTap: () => showSupportOptionsSheet(context, theme: theme),
        ),
        ProfileMenuItemSpec(
          icon: Icons.logout_rounded,
          label: 'Log Out',
          onTap: onLogOut,
          showDivider: false,
        ),
      ],
      footer: _BannerAutoDismissRow(
        iconColor: AppColors.gold,
        badgeColor: badgeColor,
        labelColor: Colors.white,
        value: appState.bannerAutoDismiss,
        onChanged: appState.setBannerAutoDismiss,
      ),
    );
  }
}

/// A device-local on/off row for the Instagram-style notification banner's
/// auto-dismiss behaviour — styled to match [ProfileMenuTile]'s badge +
/// label layout, but with a trailing [Switch] instead of a chevron/onTap,
/// since it's a toggle rather than a navigable row.
class _BannerAutoDismissRow extends StatelessWidget {
  const _BannerAutoDismissRow({
    required this.iconColor,
    required this.badgeColor,
    required this.labelColor,
    required this.value,
    required this.onChanged,
  });

  final Color iconColor;
  final Color badgeColor;
  final Color labelColor;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
            child: Icon(Icons.timer_outlined, color: iconColor, size: 19),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-dismiss Notification Banners',
                  style: AppTextStyles.body(color: labelColor, size: 15.5, weight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  value ? 'Disappears automatically after 3 seconds' : 'Keep until swiped away',
                  style: AppTextStyles.body(color: labelColor.withValues(alpha: 0.6), size: 12),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged, activeColor: iconColor),
        ],
      ),
    );
  }
}
