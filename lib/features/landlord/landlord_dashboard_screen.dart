import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/notification_offer.dart';
import '../../state/app_state.dart';
import '../../widgets/dashboard_tab_scaffold.dart';
import 'landlord_bookings_screen.dart';
import 'landlord_home_tab.dart';
import 'landlord_messages_screen.dart';
import 'landlord_profile_screen.dart';
import 'widgets/landlord_bottom_nav.dart';
import '../../core/log_out.dart';

/// Landlord dashboard shell: four tabs (Home / Messages / Bookings /
/// Profile Settings) switched by [LandlordBottomNav], matching the redesign
/// mockups. Each tab is its own screen; this widget just tracks which one
/// is showing and floats the nav bar over it.
class LandlordDashboardScreen extends StatefulWidget {
  const LandlordDashboardScreen({super.key});

  @override
  State<LandlordDashboardScreen> createState() => _LandlordDashboardScreenState();
}

class _LandlordDashboardScreenState extends State<LandlordDashboardScreen> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) offerBrowserNotifications(context);
    });
  }

  Future<void> _logOut(BuildContext context) => logOutAndGo(context, '/get-started');

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppState>().dashboardTheme;

    return DashboardTabScaffold(
      background: theme.background,
      navBar: LandlordBottomNav(currentIndex: _navIndex, onTap: (i) => setState(() => _navIndex = i)),
      body: IndexedStack(
        index: _navIndex,
        children: [
          LandlordHomeTab(
            theme: theme,
            onOpenBookings: () => setState(() => _navIndex = 2),
            onOpenProfile: () => setState(() => _navIndex = 3),
          ),
          LandlordMessagesScreen(theme: theme),
          LandlordBookingsScreen(theme: theme),
          LandlordProfileScreen(
            onLogOut: () => _logOut(context),
            onOverview: () => setState(() => _navIndex = 0),
          ),
        ],
      ),
    );
  }
}
