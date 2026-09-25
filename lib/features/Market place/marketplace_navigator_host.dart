import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import 'marketplace_auth_screen.dart';
import 'vendor_dashboard_screen.dart';

/// Hosts the entire Marketplace flow (customer shopping and the vendor
/// side) in its own nested [Navigator], reached as a single push from a
/// dashboard's bottom nav.
///
/// Every Marketplace screen navigates with plain `Navigator.of(context)`
/// pushes rather than go_router routes, so on Flutter Web those pushes
/// never touch the browser's URL/history. Without this wrapper, pressing
/// the browser back button while several screens deep in the Marketplace
/// went straight to go_router's back-button handling, which jumped to
/// whatever URL preceded `/dashboard` (typically the login screen) instead
/// of stepping back one Marketplace screen at a time. [NavigatorPopHandler]
/// lets this nested Navigator claim the back button first: it pops its own
/// stack while there's more than one route on it, and only lets the press
/// fall through to go_router (popping back to the dashboard) once this
/// Navigator is back down to its single root route.
class MarketplaceNavigatorHost extends StatefulWidget {
  const MarketplaceNavigatorHost({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<MarketplaceNavigatorHost> createState() => _MarketplaceNavigatorHostState();
}

class _MarketplaceNavigatorHostState extends State<MarketplaceNavigatorHost> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool? _startAtVendorDashboard;

  @override
  void initState() {
    super.initState();
    _resolveStartRoute();
  }

  /// A signed-in account that already has a vendor shop (same login/session
  /// as everywhere else in the app — see AppState.hasVendorProfile)
  /// shouldn't have to re-authenticate or pick "Become a Vendor" again just
  /// to reopen the Marketplace; only an account with no session, or one
  /// with no shop yet, sees the customer/vendor choice screen.
  Future<void> _resolveStartRoute() async {
    final appState = context.read<AppState>();
    if (!appState.isAuthenticated) {
      setState(() => _startAtVendorDashboard = false);
      return;
    }
    final existing = appState.hasVendorProfile;
    final hasProfile = existing ?? await appState.checkVendorProfile();
    if (!mounted) return;
    setState(() => _startAtVendorDashboard = hasProfile);
  }

  @override
  Widget build(BuildContext context) {
    final startAtVendorDashboard = _startAtVendorDashboard;
    if (startAtVendorDashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return NavigatorPopHandler(
      onPopWithResult: (result) => _navigatorKey.currentState?.maybePop(),
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => startAtVendorDashboard
              ? VendorDashboardScreen(theme: widget.theme)
              : MarketplaceAuthScreen(theme: widget.theme),
        ),
      ),
    );
  }
}
