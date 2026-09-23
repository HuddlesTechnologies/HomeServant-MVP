import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'admin_dashboard_tab.dart';
import 'admin_marketplace_tab.dart';
import 'admin_properties_tab.dart';
import 'admin_users_tab.dart';
import 'admin_vendors_tab.dart';

/// Navigation shell for the whole admin console — a bottom nav switching
/// between the five moderation areas, matching the tab-shell pattern
/// every other role's dashboard already uses in this app.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  static final _tabs = [
    const AdminDashboardTab(),
    const AdminUsersTab(),
    const AdminVendorsTab(),
    const AdminPropertiesTab(),
    const AdminMarketplaceTab(),
  ];

  Future<void> _logOut(BuildContext context) async {
    await context.read<AppState>().logout();
    if (context.mounted) context.go('/admin-login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text('Admin Console', style: AppTextStyles.heading(color: Colors.white, size: 18)),
        actions: [
          IconButton(
            onPressed: () => _logOut(context),
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Log out',
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.navy.withValues(alpha: 0.1),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Users'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'Vendors'),
          NavigationDestination(icon: Icon(Icons.home_work_outlined), selectedIcon: Icon(Icons.home_work_rounded), label: 'Properties'),
          NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), selectedIcon: Icon(Icons.shopping_bag_rounded), label: 'Marketplace'),
        ],
      ),
    );
  }
}
