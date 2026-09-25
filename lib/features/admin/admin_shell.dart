import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/change_password_sheet.dart';
import '../../widgets/notification_bell.dart';
import '../dashboard/notifications_screen.dart';
import 'admin_admins_tab.dart';
import 'admin_dashboard_tab.dart';
import 'admin_marketplace_tab.dart';
import 'admin_messages_tab.dart';
import 'admin_properties_tab.dart';
import 'admin_reports_tab.dart';
import 'admin_users_tab.dart';
import 'admin_vendors_tab.dart';

/// Auto-signs the console out after this long with no pointer activity —
/// an unattended admin session is a much bigger blast radius than a
/// regular user's, so it gets its own (shorter, non-configurable) timeout
/// distinct from the tenant/landlord app's optional App Lock.
const _idleTimeout = Duration(minutes: 15);

/// Navigation shell for the whole admin console — a bottom nav switching
/// between moderation areas, matching the tab-shell pattern every other
/// role's dashboard already uses in this app. The "Admins" destination
/// appears for MODERATOR and up — a MODERATOR only sees a read-only list
/// plus the "reset another admin's password" action there (see
/// AdminAdminsTab), while creating/removing admins and changing
/// levels/2FA stays SUPER_ADMIN-only within that same screen. Every write
/// is independently re-checked server-side (AdminLevelGuard) regardless
/// of what's shown here.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  Timer? _idleTimer;
  int _openReportsCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptPasswordChange());
    _resetIdleTimer();
    _loadOpenReportsCount();
    // Unlike tenant/landlord, an admin session's `_loadInitialData` skips
    // `loadNotifications()` entirely (it only loads the admin level + opens
    // the chat socket) — so without this, `AppState.unreadNotificationCount`
    // would just stay 0 forever and the bell below would never show a dot.
    context.read<AppState>().loadNotifications();
  }

  Future<void> _loadOpenReportsCount() async {
    try {
      final count = await context.read<AppState>().admin.openReportsCount();
      if (!mounted) return;
      setState(() => _openReportsCount = count);
    } catch (_) {
      // Best-effort — the Reports tab itself still loads the real list;
      // this only affects the nav badge.
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _onIdleTimeout);
  }

  Future<void> _onIdleTimeout() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await context.read<AppState>().logout();
    if (!mounted) return;
    context.go('/admin-login');
    messenger.showSnackBar(const SnackBar(content: Text('Signed out after 15 minutes of inactivity')));
  }

  /// Blocking, not just advisory — an admin created via the console's
  /// invite flow is still signed in with the one-time temp password from
  /// their invite email, and re-shows itself after a cancelled sheet
  /// (mustChangePassword only clears once AppState.changePassword
  /// actually succeeds) so it can't just be dismissed away.
  Future<void> _maybePromptPasswordChange() async {
    if (!mounted || !context.read<AppState>().mustChangePassword) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text("You're using a temporary password"),
          content: const Text('Set your own password to continue using the admin console.'),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await showChangePasswordSheet(context);
                if (mounted) _maybePromptPasswordChange();
              },
              child: const Text('Change Password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    final appState = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Account Settings', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Two-Factor Authentication', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 14)),
                        Text('Require a one-time code by email at login', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12)),
                      ],
                    ),
                  ),
                  Switch(
                    value: appState.twoFactorEnabled,
                    onChanged: (value) async {
                      await appState.setTwoFactorEnabled(value);
                      setSheetState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showChangePasswordSheet(context);
                  },
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Change Password'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _baseTabs = [
    AdminDashboardTab(),
    AdminUsersTab(),
    AdminVendorsTab(),
    AdminPropertiesTab(),
    AdminMarketplaceTab(),
    AdminReportsTab(),
    AdminMessagesTab(),
  ];

  /// Not `static const` like the old list — the Reports destination's icon
  /// carries a live open-reports-count badge (`_openReportsCount`), so this
  /// has to be rebuilt from instance state rather than fixed at compile time.
  List<NavigationDestination> get _baseDestinations => [
    const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
    const NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Users'),
    const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'Vendors'),
    const NavigationDestination(icon: Icon(Icons.home_work_outlined), selectedIcon: Icon(Icons.home_work_rounded), label: 'Properties'),
    const NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), selectedIcon: Icon(Icons.shopping_bag_rounded), label: 'Marketplace'),
    NavigationDestination(
      icon: _badgedIcon(Icons.flag_outlined, _openReportsCount),
      selectedIcon: _badgedIcon(Icons.flag_rounded, _openReportsCount),
      label: 'Reports',
    ),
    const NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum_rounded), label: 'Messages'),
  ];

  /// Numeric unread/open-count badge matching the style the vendor
  /// dashboard's bell already uses (`VendorDashboardScreen`'s
  /// `_openNotifications` icon — a `Stack` + `Positioned` count `Container`)
  /// rather than `NotificationBell`'s plain dot, since a bare dot can't
  /// convey "how many" the way this destination needs to.
  Widget _badgedIcon(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          top: -4,
          right: -6,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _logOut(BuildContext context) async {
    await context.read<AppState>().logout();
    if (context.mounted) context.go('/admin-login');
  }

  @override
  Widget build(BuildContext context) {
    final canSeeAdmins = context.watch<AppState>().adminLevel?.atLeastModerator ?? false;
    final tabs = canSeeAdmins ? [..._baseTabs, const AdminAdminsTab()] : _baseTabs;
    final destinations = canSeeAdmins
        ? [
            ..._baseDestinations,
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings_rounded),
              label: 'Admins',
            ),
          ]
        : _baseDestinations;
    final index = _index >= tabs.length ? 0 : _index;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerSignal: (_) => _resetIdleTimer(),
      child: _buildScaffold(context, tabs, destinations, index),
    );
  }

  Widget _buildScaffold(BuildContext context, List<Widget> tabs, List<NavigationDestination> destinations, int index) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text('Admin Console', style: AppTextStyles.heading(color: Colors.white, size: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: NotificationBell(
              color: Colors.white,
              showDot: context.watch<AppState>().unreadNotificationCount > 0,
              onTap: () {
                context.read<AppState>().markAllNotificationsRead();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen(theme: DashboardTheme.classic)),
                );
              },
            ),
          ),
          IconButton(
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'Account settings',
          ),
          IconButton(
            onPressed: () => _logOut(context),
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Log out',
          ),
        ],
      ),
      body: IndexedStack(index: index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => _index = value),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.navy.withValues(alpha: 0.1),
        destinations: destinations,
      ),
    );
  }
}
