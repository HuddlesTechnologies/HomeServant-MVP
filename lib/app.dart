import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'routes/app_router.dart';
import 'state/app_state.dart';
import 'widgets/app_lock_gate.dart';
import 'widgets/notification_banner_overlay.dart';
import 'widgets/session_expired_gate.dart';

class HomeServantApp extends StatefulWidget {
  const HomeServantApp({super.key});
  @override
  State<HomeServantApp> createState() => _HomeServantAppState();
}

class _HomeServantAppState extends State<HomeServantApp> {
  late final AppState _appState = AppState();
  late final GoRouter _router = buildAppRouter(_appState);

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: restores the previous session's saved state (if any).
    // The UI mounts immediately with defaults and simply rebuilds once this
    // resolves, via the ChangeNotifierProvider below — no loading gate needed
    // since a local read is fast enough that this is imperceptible.
    _appState.load();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: MaterialApp.router(
        title: 'Home Servant',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        // Every screen hardcodes AppColors.* directly rather than reading
        // Theme.of(context).colorScheme (58 files and counting, none
        // theme-aware) — wiring up a darkTheme here without that groundwork
        // would only flip the handful of Material-default surfaces
        // (dialogs, default text) to dark while every custom screen stayed
        // hardcoded light, which reads as broken, not as dark mode. Pinning
        // this explicitly documents that as a deliberate scope decision
        // rather than an oversight; a real dark mode needs that refactor
        // done first.
        themeMode: ThemeMode.light,
        routerConfig: _router,
        builder: (context, child) =>
            SessionExpiredGate(child: AppLockGate(child: NotificationBannerOverlay(child: child!))),
      ),
    );
  }
}
