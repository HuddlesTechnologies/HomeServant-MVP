import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'routes/app_router.dart';
import 'state/app_state.dart';
import 'widgets/app_lock_gate.dart';
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
        routerConfig: _router,
        builder: (context, child) => SessionExpiredGate(child: AppLockGate(child: child!)),
      ),
    );
  }
}
