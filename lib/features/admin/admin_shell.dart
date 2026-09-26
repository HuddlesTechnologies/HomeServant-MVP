import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/vendor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/change_password_sheet.dart';
import '../../widgets/notification_bell.dart';
import '../dashboard/notifications_screen.dart';
import 'admin_activity_log_screen.dart';
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

  // Nav badge counts — each best-effort loaded once at console startup (see
  // [_loadBadgeCounts]); a failed fetch just leaves that one badge at 0
  // rather than blocking the console or the others. Vendors/Reports badge
  // their own primary tab; the rest badge their tile inside the "More"
  // sheet (see [_moreItems]) and roll up into that sheet's own nav badge.
  int _openReportsCount = 0;
  int _pendingVendorsCount = 0;
  int _openPropertyReportsCount = 0;
  int _openMarketplaceReportsCount = 0;
  int _messagesAttentionCount = 0;
  int _pendingAdminInvitesCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptPasswordChange());
    _resetIdleTimer();
    _loadBadgeCounts();
    // Unlike tenant/landlord, an admin session's `_loadInitialData` skips
    // `loadNotifications()` entirely (it only loads the admin level + opens
    // the chat socket) — so without this, `AppState.unreadNotificationCount`
    // would just stay 0 forever and the bell below would never show a dot.
    context.read<AppState>().loadNotifications();
  }

  void _loadBadgeCounts() {
    final admin = context.read<AppState>().admin;
    admin.openReportsCount().then((c) {
      if (mounted) setState(() => _openReportsCount = c);
    }).catchError((_) {});
    admin.pendingVendorsCount().then((c) {
      if (mounted) setState(() => _pendingVendorsCount = c);
    }).catchError((_) {});
    admin.openReportsCount(targetType: ReportTargetType.property).then((c) {
      if (mounted) setState(() => _openPropertyReportsCount = c);
    }).catchError((_) {});
    admin.openReportsCount(targetType: ReportTargetType.marketplaceItem).then((c) {
      if (mounted) setState(() => _openMarketplaceReportsCount = c);
    }).catchError((_) {});
    admin.messagesAttentionCount().then((c) {
      if (mounted) setState(() => _messagesAttentionCount = c);
    }).catchError((_) {});
    admin.pendingAdminInvitesCount().then((c) {
      if (mounted) setState(() => _pendingAdminInvitesCount = c);
    }).catchError((_) {});
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

  // Only 4 destinations sit in the persistent bottom nav (the 5th slot is
  // "More") — Apple's HIG caps a tab bar at 5 items and folds the rest into
  // a "More" tab (exactly what UIKit's UITabBarController does on its own
  // past 5 children); everything past that count reads as clutter and
  // starts pushing labels to truncate on smaller phones. These four are the
  // areas most likely to need a quick check-in; Properties, Marketplace,
  // Messages, and (conditionally) Admins move into the "More" sheet below.
  // Not `static const` — the Users/Vendors tabs can be handed a
  // dashboard-requested initial filter (see [_handleDashboardNavigate]),
  // and a fresh [ValueKey] per "epoch" forces a real remount so that
  // filter actually takes effect (a rebuilt widget with a new constructor
  // arg alone wouldn't re-run the target's `late` field initializers).
  // Plain bottom-nav tab switches don't touch the epoch, so a manually
  // chosen filter still survives navigating away and back.
  UserRole? _usersInitialRoleFilter;
  bool _usersInitialDeactivatedOnly = false;
  int _usersTabEpoch = 0;
  VendorApplicationStatus? _vendorsInitialStatusFilter;
  int _vendorsTabEpoch = 0;

  List<Widget> get _primaryTabs => [
    AdminDashboardTab(onNavigate: _handleDashboardNavigate),
    AdminUsersTab(
      key: ValueKey('admin-users-tab-$_usersTabEpoch'),
      initialRoleFilter: _usersInitialRoleFilter,
      initialShowDeactivatedOnly: _usersInitialDeactivatedOnly,
    ),
    AdminVendorsTab(
      key: ValueKey('admin-vendors-tab-$_vendorsTabEpoch'),
      initialStatusFilter: _vendorsInitialStatusFilter,
    ),
    const AdminReportsTab(),
  ];

  void _goToUsers({UserRole? roleFilter, bool deactivatedOnly = false}) {
    setState(() {
      _usersInitialRoleFilter = roleFilter;
      _usersInitialDeactivatedOnly = deactivatedOnly;
      _usersTabEpoch++;
      _index = 1;
    });
  }

  void _goToVendors({VendorApplicationStatus? statusFilter}) {
    setState(() {
      _vendorsInitialStatusFilter = statusFilter;
      _vendorsTabEpoch++;
      _index = 2;
    });
  }

  void _handleDashboardNavigate(AdminDashboardDestination destination) {
    switch (destination) {
      case AdminDashboardDestination.totalUsers:
        _goToUsers();
      case AdminDashboardDestination.tenants:
        _goToUsers(roleFilter: UserRole.tenant);
      case AdminDashboardDestination.landlords:
        _goToUsers(roleFilter: UserRole.landlord);
      case AdminDashboardDestination.deactivatedAccounts:
        _goToUsers(deactivatedOnly: true);
      case AdminDashboardDestination.vendors:
        _goToVendors();
      case AdminDashboardDestination.pendingVendors:
        _goToVendors(statusFilter: VendorApplicationStatus.pending);
      case AdminDashboardDestination.activeVendors:
        // No separate "active" status exists on VendorApplicationStatus —
        // an active shop is always an approved one, so this is the closest
        // filter that actually narrows the list.
        _goToVendors(statusFilter: VendorApplicationStatus.approved);
      case AdminDashboardDestination.properties:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const _MoreScreen(item: _MoreItem(icon: Icons.home_work_outlined, label: 'Properties', builder: AdminPropertiesTab.new)),
          ),
        );
      case AdminDashboardDestination.marketplaceOrders:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _MoreScreen(
              item: _MoreItem(icon: Icons.shopping_bag_outlined, label: 'Marketplace', builder: () => const AdminMarketplaceTab(initialShowOrders: true)),
            ),
          ),
        );
    }
  }

  /// Not `static const` like the old list — the Vendors/Reports
  /// destinations' icons carry live badge counts, so this has to be
  /// rebuilt from instance state rather than fixed at compile time.
  List<NavigationDestination> get _primaryDestinations => [
    const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
    const NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Users'),
    NavigationDestination(
      icon: _badgedIcon(Icons.storefront_outlined, _pendingVendorsCount),
      selectedIcon: _badgedIcon(Icons.storefront_rounded, _pendingVendorsCount),
      label: 'Vendors',
    ),
    NavigationDestination(
      icon: _badgedIcon(Icons.flag_outlined, _openReportsCount),
      selectedIcon: _badgedIcon(Icons.flag_rounded, _openReportsCount),
      label: 'Reports',
    ),
  ];

  /// One entry per screen folded into the "More" tab — pushed on top of the
  /// shell via Navigator rather than kept in the IndexedStack, same as a
  /// native "More" list pushing into its own detail screens. [count] backs
  /// both that item's own row badge and the "More" nav destination's total
  /// (see [_moreAttentionTotal]/[_openMoreSheet]).
  List<_MoreItem> _moreItems(bool canSeeAdmins) => [
    _MoreItem(icon: Icons.home_work_outlined, label: 'Properties', count: _openPropertyReportsCount, builder: AdminPropertiesTab.new),
    _MoreItem(
      icon: Icons.shopping_bag_outlined,
      label: 'Marketplace',
      count: _openMarketplaceReportsCount,
      builder: AdminMarketplaceTab.new,
    ),
    _MoreItem(icon: Icons.forum_outlined, label: 'Messages', count: _messagesAttentionCount, builder: AdminMessagesTab.new),
    if (canSeeAdmins) ...[
      _MoreItem(icon: Icons.admin_panel_settings_outlined, label: 'Admins', count: _pendingAdminInvitesCount, builder: AdminAdminsTab.new),
      const _MoreItem(icon: Icons.history_rounded, label: 'Activity Log', builder: AdminActivityLogScreen.new),
    ],
  ];

  int _moreAttentionTotal(bool canSeeAdmins) => _moreItems(canSeeAdmins).fold<int>(0, (sum, item) => sum + item.count);

  void _openMoreSheet(BuildContext context, bool canSeeAdmins) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text('More', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
            ),
            for (final item in _moreItems(canSeeAdmins))
              ListTile(
                leading: Icon(item.icon, color: AppColors.navy),
                title: Text(item.label, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600)),
                trailing: item.count > 0 ? _CountBadge(count: item.count) : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _MoreScreen(item: item)));
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

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
    final index = _index >= _primaryTabs.length ? 0 : _index;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerSignal: (_) => _resetIdleTimer(),
      child: _buildScaffold(context, canSeeAdmins, index),
    );
  }

  Widget _buildScaffold(BuildContext context, bool canSeeAdmins, int index) {
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
      body: IndexedStack(index: index, children: _primaryTabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          if (value == _primaryTabs.length) {
            _openMoreSheet(context, canSeeAdmins);
            return;
          }
          setState(() => _index = value);
        },
        backgroundColor: Colors.white,
        indicatorColor: AppColors.navy.withValues(alpha: 0.1),
        destinations: [
          ..._primaryDestinations,
          NavigationDestination(
            icon: _badgedIcon(Icons.more_horiz_rounded, _moreAttentionTotal(canSeeAdmins)),
            selectedIcon: _badgedIcon(Icons.more_horiz_rounded, _moreAttentionTotal(canSeeAdmins)),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

/// One screen folded into the admin console's "More" tab. [count] is its
/// unattended-activity badge — 0 for a screen with no such concept (e.g.
/// Activity Log).
class _MoreItem {
  const _MoreItem({required this.icon, required this.label, this.count = 0, required this.builder});

  final IconData icon;
  final String label;
  final int count;
  final Widget Function() builder;
}

/// Small numeric badge for a "More" sheet row — same red-circle convention
/// as [_AdminShellState._badgedIcon], just laid out inline as a `trailing`
/// widget instead of overlaid on an icon.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      constraints: const BoxConstraints(minWidth: 22),
      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.item});

  final _MoreItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(item.label, style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: item.builder(),
    );
  }
}
