import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../widgets/confirm_sheet.dart';

/// Asks the user to confirm, then signs out and goes to [route] (the
/// sign-in or Get Started screen). Shared by the tenant, landlord and admin
/// log-out buttons.
Future<void> logOutAndGo(BuildContext context, String route) async {
  final confirmed = await showConfirmSheet(
    context,
    title: 'Log out?',
    body: "You'll need to sign in again to use your account on this device.",
    actionLabel: 'Log out',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  try {
    await context.read<AppState>().logout();
  } catch (_) {
    // Local session is torn down in AppState.logout()'s finally block
    // regardless; still navigate away rather than leaving the user
    // stranded on a screen that thinks it's logged out.
  }
  if (context.mounted) context.go(route);
}
