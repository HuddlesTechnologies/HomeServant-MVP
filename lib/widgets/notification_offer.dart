import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../services/browser_notifications.dart';
import '../state/app_state.dart';

bool _offeredThisSession = false;

/// On web, once per page load while the browser hasn't been asked yet:
/// offers to turn on notifications, which also registers this browser for
/// push so messages and booking updates arrive even when the site is
/// closed. The permission prompt itself only comes from the "Turn on" tap
/// (browsers ignore one that isn't tied to a user action).
void offerBrowserNotifications(BuildContext context, {String? message}) {
  if (_offeredThisSession || !browserNotificationsSupported || browserNotificationPermission != 'default') return;
  _offeredThisSession = true;
  final appState = context.read<AppState>();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 12),
      backgroundColor: AppColors.navy,
      content: Text(
        message ?? 'Get notified about new messages and booking updates, even when HomeServant is closed?',
        style: AppTextStyles.body(color: AppColors.white, size: 14),
      ),
      action: SnackBarAction(
        label: 'Turn on',
        textColor: AppColors.gold,
        onPressed: () => appState.enableWebPush(),
      ),
    ),
  );
}
