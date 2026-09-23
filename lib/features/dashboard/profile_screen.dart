import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/app_state.dart';
import '../../widgets/invite_friends_sheet.dart';
import '../../widgets/profile_edit_button.dart';
import '../../widgets/profile_menu_tile.dart';
import '../../widgets/theme_picker_sheet.dart';
import '../../widgets/upload_picker.dart';
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
      children: [
        const SizedBox(height: 20),
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: theme.foreground, width: 1.4),
            image: photoPath != null
                ? DecorationImage(image: imageProviderForPath(photoPath), fit: BoxFit.cover)
                : null,
          ),
          child: photoPath == null ? Icon(Icons.person_outline, color: theme.foreground, size: 40) : null,
        ),
        const SizedBox(height: 16),
        ProfileEditButton(
          color: theme.accent,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
        ),
        const SizedBox(height: 20),
        Divider(color: theme.foreground.withValues(alpha: 0.15), height: 1),
        ProfileMenuTile(
          icon: Icons.favorite_border_rounded,
          label: 'WishList',
          iconColor: theme.accent,
          badgeColor: badgeColor,
          labelColor: theme.foreground,
          dividerColor: theme.foreground.withValues(alpha: 0.15),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WishlistScreen(theme: theme))),
        ),
        ProfileMenuTile(
          icon: Icons.history_rounded,
          label: 'History',
          iconColor: theme.accent,
          badgeColor: badgeColor,
          labelColor: theme.foreground,
          dividerColor: theme.foreground.withValues(alpha: 0.15),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HistoryScreen(theme: theme))),
        ),
        ProfileMenuTile(
          icon: Icons.settings_outlined,
          label: 'Settings',
          iconColor: theme.accent,
          badgeColor: badgeColor,
          labelColor: theme.foreground,
          dividerColor: theme.foreground.withValues(alpha: 0.15),
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsScreen(theme: theme, onAccountClosed: onLogOut)),
              ),
        ),
        ProfileMenuTile(
          icon: Icons.remove_red_eye_outlined,
          label: 'Theme',
          iconColor: theme.accent,
          badgeColor: badgeColor,
          labelColor: theme.foreground,
          dividerColor: theme.foreground.withValues(alpha: 0.15),
          onTap: () async {
            final picked = await showThemePickerSheet(context, current: theme);
            if (picked != null && context.mounted) {
              context.read<AppState>().setDashboardTheme(picked);
            }
          },
        ),
        ProfileMenuTile(
          icon: Icons.person_add_alt_outlined,
          label: 'Invite Friends',
          iconColor: theme.accent,
          badgeColor: badgeColor,
          labelColor: theme.foreground,
          dividerColor: theme.foreground.withValues(alpha: 0.15),
          onTap: () => showInviteFriendsSheet(context, theme: theme),
        ),
        ProfileMenuTile(
          icon: Icons.logout_rounded,
          label: 'Log Out',
          iconColor: theme.accent,
          badgeColor: badgeColor,
          labelColor: theme.foreground,
          dividerColor: theme.foreground.withValues(alpha: 0.15),
          onTap: onLogOut,
          showDivider: false,
        ),
      ],
    );
  }
}
