import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

/// Signs out and goes to [route] (the sign-in or Get Started screen).
/// Shared by the tenant, landlord and admin log-out buttons.
Future<void> logOutAndGo(BuildContext context, String route) async {
  try {
    await context.read<AppState>().logout();
  } catch (_) {
    // Local session is torn down in AppState.logout()'s finally block
    // regardless; still navigate away rather than leaving the user
    // stranded on a screen that thinks it's logged out.
  }
  if (context.mounted) context.go(route);
}
