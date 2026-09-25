import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../widgets/invite_friends_sheet.dart';
import '../../widgets/profile_menu_scaffold.dart';
import '../../widgets/theme_picker_sheet.dart';
import 'edit_profile_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'wishlist_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.onLogOut});

  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = appState.dashboardTheme;
    final photoPath = appState.profilePhotoPath;
    final badgeColor = Color.alphaBlend(theme.foreground.withValues(alpha: 0.14), theme.background);
    final dividerColor = theme.foreground.withValues(alpha: 0.15);

    return ProfileMenuScaffold(
      backgroundColor: theme.background,
      iconColor: theme.accent,
      labelColor: theme.foreground,
      badgeColor: badgeColor,
      dividerColor: dividerColor,
      photoPath: photoPath,
      photoBorderColor: theme.foreground,
      editButtonColor: theme.accent,
      onEditProfileTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
      items: [
        ProfileMenuItemSpec(
          icon: Icons.favorite_border_rounded,
          label: 'WishList',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WishlistScreen(theme: theme))),
        ),
        ProfileMenuItemSpec(
          icon: Icons.history_rounded,
          label: 'History',
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(theme: theme))),
        ),
        ProfileMenuItemSpec(
          icon: Icons.settings_outlined,
          label: 'Settings',
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsScreen(theme: theme, onAccountClosed: onLogOut)),
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
          icon: Icons.person_add_alt_outlined,
          label: 'Invite Friends',
          onTap: () => showInviteFriendsSheet(context, theme: theme),
        ),
        ProfileMenuItemSpec(
          icon: Icons.logout_rounded,
          label: 'Log Out',
          onTap: onLogOut,
          showDivider: false,
        ),
      ],
    );
  }
}
