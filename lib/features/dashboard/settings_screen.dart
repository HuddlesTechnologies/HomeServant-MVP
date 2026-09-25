import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/app_lock_pin_sheet.dart';
import '../../widgets/change_password_sheet.dart';
import '../../widgets/dashboard_page_scaffold.dart';
import '../../widgets/support_sheet.dart';
import 'legal/tenancy_agreements_screen.dart';
import 'privacy&terms_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.theme, required this.onAccountClosed});

  final DashboardTheme theme;

  /// Deactivating/deleting the account ends the session the same way
  /// logging out does — reuses the callback `ProfileScreen` already gets
  /// for that, so the navigation-back-to-get-started logic lives in one
  /// place.
  final VoidCallback onAccountClosed;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: 'Settings',
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _SectionHeader(theme: theme, label: 'Account & Security'),
              _SettingsCard(
                theme: theme,
                children: [
                  _NavRow(
                    theme: theme,
                    icon: Icons.lock_reset_rounded,
                    label: 'Change Password',
                    onTap: () => _openChangePassword(context),
                  ),
                  _SwitchRow(
                    theme: theme,
                    icon: Icons.verified_user_outlined,
                    label: 'Two-Factor Authentication',
                    subtitle: 'Require a one-time code by email at login',
                    value: appState.twoFactorEnabled,
                    onChanged: (value) => _onToggleTwoFactor(context, appState, value),
                    // App Lock (below) doesn't exist on web — there's no
                    // device to reopen a PIN gate on — so this is the last
                    // row there and shouldn't draw a trailing divider.
                    showDivider: !kIsWeb,
                  ),
                  if (!kIsWeb)
                    _SwitchRow(
                      theme: theme,
                      icon: Icons.pin_outlined,
                      label: 'App Lock',
                      subtitle: 'Require a PIN whenever the app reopens',
                      value: appState.appLockEnabled,
                      onChanged: (value) => _onToggleAppLock(context, appState, value),
                      showDivider: false,
                    ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionHeader(theme: theme, label: 'Notifications'),
              _SettingsCard(
                theme: theme,
                children: [
                  _SwitchRow(
                    theme: theme,
                    icon: Icons.notifications_active_outlined,
                    label: 'Push Notifications',
                    value: appState.pushNotificationsEnabled,
                    onChanged: appState.setPushNotificationsEnabled,
                  ),
                  Opacity(
                    opacity: appState.pushNotificationsEnabled ? 1 : 0.4,
                    child: IgnorePointer(
                      ignoring: !appState.pushNotificationsEnabled,
                      child: Column(
                        children: [
                          _SwitchRow(
                            theme: theme,
                            icon: Icons.chat_bubble_outline_rounded,
                            label: 'New Messages',
                            value: appState.newMessageNotifications,
                            onChanged: appState.setNewMessageNotifications,
                          ),
                          _SwitchRow(
                            theme: theme,
                            icon: Icons.home_work_outlined,
                            label: 'Property Updates',
                            value: appState.propertyUpdateNotifications,
                            onChanged: appState.setPropertyUpdateNotifications,
                          ),
                          _SwitchRow(
                            theme: theme,
                            icon: Icons.trending_down_rounded,
                            label: 'Wishlist Price Drops',
                            subtitle: 'Get notified when a saved property gets cheaper',
                            value: appState.wishlistPriceDropAlerts,
                            onChanged: appState.setWishlistPriceDropAlerts,
                          ),
                          _SwitchRow(
                            theme: theme,
                            icon: Icons.local_offer_outlined,
                            label: 'Promotions & Offers',
                            value: appState.promotionalNotifications,
                            onChanged: appState.setPromotionalNotifications,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Deliberately outside the Push Notifications-gated group
                  // above: this governs the in-app realtime banner (socket-
                  // driven, shown while the app is already open), not
                  // whether a notification is delivered at all — so it
                  // stays live even with push notifications toggled off.
                  _SwitchRow(
                    theme: theme,
                    icon: Icons.timer_outlined,
                    label: 'Auto-dismiss Notification Banners',
                    subtitle: appState.bannerAutoDismiss
                        ? 'Disappears automatically after 3 seconds'
                        : 'Keep until swiped away',
                    value: appState.bannerAutoDismiss,
                    onChanged: appState.setBannerAutoDismiss,
                    showDivider: false,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionHeader(theme: theme, label: 'Support & Legal'),
              _SettingsCard(
                theme: theme,
                children: [
                  _NavRow(
                    theme: theme,
                    icon: Icons.support_agent_rounded,
                    label: 'Help & Support',
                    onTap: () => showSupportOptionsSheet(context, theme: theme),
                  ),
                  _NavRow(
                    theme: theme,
                    icon: Icons.privacy_tip_outlined,
                    label: 'Privacy Policy',
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalDocumentScreen(theme: theme, kind: LegalDocumentKind.privacyPolicy),
                          ),
                        ),
                  ),
                  _NavRow(
                    theme: theme,
                    icon: Icons.description_outlined,
                    label: 'Terms of Service',
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => LegalDocumentScreen(theme: theme, kind: LegalDocumentKind.termsOfService),
                          ),
                        ),
                  ),
                  _NavRow(
                    theme: theme,
                    icon: Icons.gavel_rounded,
                    label: 'Tenancy Agreements',
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => TenancyAgreementsScreen(theme: theme)),
                        ),
                    showDivider: false,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _SectionHeader(theme: theme, label: 'Danger Zone', color: Colors.redAccent),
              _SettingsCard(
                theme: theme,
                children: [
                  _NavRow(
                    theme: theme,
                    icon: Icons.pause_circle_outline_rounded,
                    label: 'Deactivate Account',
                    labelColor: Colors.redAccent,
                    onTap:
                        () => _confirmAccountAction(
                          context,
                          title: 'Deactivate account?',
                          body:
                              "Your profile will be hidden and you'll be signed out. You can reactivate any time "
                              "within 30 days just by logging back in — after that, your account and its data "
                              'will be permanently deleted. We\'ll email you when this happens.',
                          actionLabel: 'Deactivate',
                          onConfirmed: () async {
                            await appState.deactivateAccount();
                            onAccountClosed();
                          },
                        ),
                  ),
                  _NavRow(
                    theme: theme,
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete Account',
                    labelColor: Colors.redAccent,
                    onTap:
                        () => _confirmAccountAction(
                          context,
                          title: 'Delete account permanently?',
                          body:
                              "This can't be undone. Your profile, wishlist, and saved settings will "
                              'all be removed.',
                          actionLabel: 'Delete',
                          onConfirmed: () async {
                            await appState.deleteAccount();
                            onAccountClosed();
                          },
                        ),
                    showDivider: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onToggleTwoFactor(BuildContext context, AppState appState, bool value) async {
    final confirmed = await _confirmSheet(
      context,
      title: value ? 'Turn on Two-Factor Authentication?' : 'Turn off Two-Factor Authentication?',
      body: value
          ? "You'll need to enter a one-time code sent to your email every time you log in."
          : 'Your account will only be protected by your password.',
      actionLabel: value ? 'Turn On' : 'Turn Off',
    );
    if (!confirmed) return;
    try {
      await appState.setTwoFactorEnabled(value);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _onToggleAppLock(BuildContext context, AppState appState, bool value) async {
    if (value) {
      final pin = await showSetAppLockPinSheet(context);
      if (pin != null) appState.enableAppLock(pin);
    } else {
      final currentPin = appState.appLockPin;
      if (currentPin == null) {
        appState.disableAppLock();
        return;
      }
      final verified = await showVerifyAppLockPinSheet(
        context,
        expectedPin: currentPin,
        title: 'Enter your PIN to turn off App Lock',
      );
      if (verified) appState.disableAppLock();
    }
  }

  void _openChangePassword(BuildContext context) {
    showChangePasswordSheet(context);
  }

  Future<void> _confirmAccountAction(
    BuildContext context, {
    required String title,
    required String body,
    required String actionLabel,
    required Future<void> Function() onConfirmed,
  }) async {
    final confirmed = await _confirmSheet(context, title: title, body: body, actionLabel: actionLabel, destructive: true);
    if (!confirmed) return;
    try {
      await onConfirmed();
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<bool> _confirmSheet(
    BuildContext context, {
    required String title,
    required String body,
    required String actionLabel,
    bool destructive = false,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _ConfirmSheet(title: title, body: body, actionLabel: actionLabel, destructive: destructive),
    );
    return result ?? false;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.theme, required this.label, this.color});

  final DashboardTheme theme;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.body(
          color: color ?? theme.foreground.withValues(alpha: 0.55),
          size: 12,
          weight: FontWeight.w700,
        ).copyWith(letterSpacing: 0.6),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.theme, required this.children});

  final DashboardTheme theme;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(children: children),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.theme,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.showDivider = true,
  });

  final DashboardTheme theme;
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: theme.accent, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.body(color: theme.onSurface, size: 14.5, weight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12)),
                    ],
                  ],
                ),
              ),
              Switch.adaptive(value: value, onChanged: onChanged, activeColor: theme.accent),
            ],
          ),
        ),
        if (showDivider) Divider(color: theme.onSurface.withValues(alpha: 0.1), height: 1),
      ],
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.theme,
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.showDivider = true,
  });

  final DashboardTheme theme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: labelColor ?? theme.accent, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body(color: labelColor ?? theme.onSurface, size: 14.5, weight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.35)),
              ],
            ),
          ),
        ),
        if (showDivider) Divider(color: theme.onSurface.withValues(alpha: 0.1), height: 1),
      ],
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.title, required this.body, required this.actionLabel, this.destructive = false});

  final String title;
  final String body;
  final String actionLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.heading(color: AppColors.navy, size: 19)),
            const SizedBox(height: 8),
            Text(body, style: AppTextStyles.body(color: AppColors.hintGrey, size: 14)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.navy),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text('Cancel', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: destructive ? Colors.redAccent : AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text(actionLabel, style: AppTextStyles.button(color: Colors.white, size: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
