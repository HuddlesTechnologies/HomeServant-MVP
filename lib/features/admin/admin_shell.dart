import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/vendor.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/change_password_sheet.dart';
import '../../widgets/notification_bell.dart';
import '../../services/browser_notifications.dart';
import '../dashboard/notifications_screen.dart';
import 'admin_activity_log_screen.dart';
import 'admin_admins_tab.dart';
import 'admin_evictions_tab.dart';
import 'admin_payouts_screen.dart';
import 'admin_platform_controls_screen.dart';
import 'admin_support_insights_tab.dart';
import 'admin_verifications_tab.dart';
import 'admin_chat_log_screen.dart';
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
  final List<StreamSubscription> _badgeSubscriptions = [];

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
  int _pendingEvictionsCount = 0;
  int _pendingVerificationsCount = 0;
  int _stuckPaymentsCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptPasswordChange();
      _maybeOfferBrowserNotifications();
    });
    _resetIdleTimer();
    _loadBadgeCounts();
    // Unlike tenant/landlord, an admin session's `_loadInitialData` skips
    // `loadNotifications()` entirely (it only loads the admin level + opens
    // the chat socket) — so without this, `AppState.unreadNotificationCount`
    // would just stay 0 forever and the bell below would never show a dot.
    context.read<AppState>().loadNotifications();
    _subscribeToLiveBadgeUpdates();
  }

  /// Without this, every one of these badges was "best-effort loaded once
  /// at console startup" (see the field doc above) — a second admin
  /// resolving a report, approving a vendor, or claiming a support thread
  /// left every *other* already-open console showing stale counts until
  /// its next restart. `admin:badges-changed` is the new event backing
  /// reports/vendors/admin-invite mutations; `message:new`/`thread:claimed`
  /// already reached every admin (see ChatGateway.broadcastToAdmins) but
  /// nothing here was listening to them yet.
  void _subscribeToLiveBadgeUpdates() {
    final chatSocket = context.read<AppState>().chatSocket;
    _badgeSubscriptions.addAll([
      chatSocket.onAdminBadgesChanged.listen((_) => _loadBadgeCounts()),
      chatSocket.onNewMessage.listen((_) => _loadBadgeCounts()),
      chatSocket.onThreadClaimed.listen((_) => _loadBadgeCounts()),
    ]);
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
    if (context.read<AppState>().adminLevel?.atLeastModerator ?? false) {
      context.read<AppState>().verification.pendingCount().then((c) {
        if (mounted) setState(() => _pendingVerificationsCount = c);
      }).catchError((_) {});
    }
    if (context.read<AppState>().adminLevel?.isSuperAdmin ?? false) {
      context.read<AppState>().verification.stuckPaymentCount().then((c) {
        if (mounted) setState(() => _stuckPaymentsCount = c);
      }).catchError((_) {});
      context.read<AppState>().evictionsRepo.adminPendingCount().then((c) {
        if (mounted) setState(() => _pendingEvictionsCount = c);
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    for (final subscription in _badgeSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _onIdleTimeout);
  }

  Future<void> _onIdleTimeout() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().logout();
    } catch (_) {
      // Local session is torn down in AppState.logout()'s finally block
      // regardless; still navigate away rather than leaving the user
      // stranded on a screen that thinks it's logged out.
    }
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

  /// On web, once per console load while the browser hasn't been asked
  /// yet: offer to turn on pop-ups for alerts that arrive while the tab
  /// isn't in view. The permission request itself only happens from the
  /// "Turn on" tap — browsers ignore one that isn't tied to a user action.
  void _maybeOfferBrowserNotifications() {
    if (!mounted || !browserNotificationsSupported || browserNotificationPermission != 'default') return;
    final appState = context.read<AppState>();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 12),
        // Explicit navy/white/gold (see AppTheme's snackBarTheme) — the
        // "Turn on" button used to be nearly invisible.
        backgroundColor: AppColors.navy,
        content: Text(
          'Get a pop-up for new chats and alerts even when this tab is in the background?',
          style: AppTextStyles.body(color: AppColors.white, size: 14),
        ),
        action: SnackBarAction(
          label: 'Turn on',
          textColor: AppColors.gold,
          onPressed: () async {
            // Also registers this browser for push, so alerts arrive
            // even when the console isn't open.
            final granted = await appState.enableWebPush();
            appState.setAdminBrowserNotifications(granted);
          },
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
              const SizedBox(height: 8),
              _SettingsSwitchRow(
                title: 'On duty',
                subtitle: appState.adminOnDuty
                    ? 'You get alert sounds for new support conversations'
                    : "Away: new support conversations arrive silently. Chats you're handling still alert you.",
                value: appState.adminOnDuty,
                onChanged: (value) async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await appState.setAdminOnDuty(value);
                  } on ApiException catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(e.message)));
                  }
                  setSheetState(() {});
                },
              ),
              const SizedBox(height: 8),
              _SettingsSwitchRow(
                title: 'Alert sounds on this device',
                subtitle: 'Play a sound for chat alerts (at most once every 10 seconds)',
                value: appState.adminAlertSound,
                onChanged: (value) {
                  appState.setAdminAlertSound(value);
                  setSheetState(() {});
                },
              ),
              if (browserNotificationsSupported) ...[
                const SizedBox(height: 8),
                _SettingsSwitchRow(
                  title: 'Browser pop-ups',
                  subtitle: switch (browserNotificationPermission) {
                    'denied' => 'Blocked in this browser. Allow notifications for this site in the browser settings.',
                    _ => "Show alerts as a pop-up when this tab isn't in view",
                  },
                  value: appState.adminBrowserNotifications && browserNotificationPermission == 'granted',
                  onChanged: (value) async {
                    if (!value) {
                      appState.setAdminBrowserNotifications(false);
                      setSheetState(() {});
                      return;
                    }
                    // Asked only from this tap: browsers ignore a
                    // permission request that isn't tied to a user action.
                    final permission = await requestBrowserNotificationPermission();
                    appState.setAdminBrowserNotifications(permission == 'granted');
                    setSheetState(() {});
                  },
                ),
              ],
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

  /// Wide screens only: a "More" page shown in the content area beside the
  /// sidebar (instead of pushed as its own screen, as on phones). Null
  /// while one of the primary tabs is showing.
  _MoreItem? _openPage;

  /// The sidebar's own expand/collapse choice; null follows the screen
  /// width (full sidebar on desktop, icons only on tablets).
  bool? _sidebarExpanded;
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
      _openPage = null;
    });
  }

  void _goToVendors({VendorApplicationStatus? statusFilter}) {
    setState(() {
      _vendorsInitialStatusFilter = statusFilter;
      _vendorsTabEpoch++;
      _index = 2;
      _openPage = null;
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
        _openMoreItem(const _MoreItem(icon: Icons.home_work_outlined, label: 'Properties', builder: AdminPropertiesTab.new));
      case AdminDashboardDestination.marketplaceOrders:
        _openMoreItem(
          _MoreItem(icon: Icons.shopping_bag_outlined, label: 'Marketplace', builder: () => const AdminMarketplaceTab(initialShowOrders: true)),
        );
    }
  }

  /// With the sidebar (wide screens) a "More" page opens beside it; on
  /// phones it's pushed as its own screen with a back button.
  void _openMoreItem(_MoreItem item) {
    if (_usesSidebar(context)) {
      setState(() => _openPage = item);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _MoreScreen(item: item)));
    }
  }

  static bool _usesSidebar(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.medium;

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
  List<_MoreItem> _moreItems(bool canSeeAdmins, bool isSuperAdmin) => [
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
      _MoreItem(icon: Icons.verified_user_outlined, label: 'ID Verifications', count: _pendingVerificationsCount, builder: AdminVerificationsTab.new),
    ],
    // Every other admin's chat history across the last 30 days — kept
    // SUPER_ADMIN-only (the server independently re-checks this too, see
    // AdminController.findChatLog) since it's not scoped to the viewing
    // admin's own conversations the way Messages is.
    if (isSuperAdmin) const _MoreItem(icon: Icons.history_edu_rounded, label: 'Chat Log', builder: AdminChatLogScreen.new),
    if (isSuperAdmin)
      const _MoreItem(icon: Icons.insights_rounded, label: 'Support Insights', builder: AdminSupportInsightsTab.new),
    if (isSuperAdmin)
      _MoreItem(icon: Icons.gavel_rounded, label: 'Eviction Requests', count: _pendingEvictionsCount, builder: AdminEvictionsTab.new),
    if (isSuperAdmin)
      const _MoreItem(icon: Icons.tune_rounded, label: 'Platform Controls', builder: AdminPlatformControlsScreen.new),
    if (isSuperAdmin)
      _MoreItem(icon: Icons.payments_outlined, label: 'Payouts & Refunds', count: _stuckPaymentsCount, builder: AdminPayoutsScreen.new),
  ];

  int _moreAttentionTotal(bool canSeeAdmins, bool isSuperAdmin) =>
      _moreItems(canSeeAdmins, isSuperAdmin).fold<int>(0, (sum, item) => sum + item.count);

  /// A super admin has a dozen entries here, more than a bottom sheet's
  /// default height (9/16 of the screen) can show, so the sheet may grow to
  /// 90% of the screen and its list scrolls: nothing is ever cut off.
  void _openMoreSheet(BuildContext context, bool canSeeAdmins, bool isSuperAdmin) {
    final items = _moreItems(canSeeAdmins, isSuperAdmin);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9, maxWidth: 640),
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
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final item in items)
                    ListTile(
                      leading: Icon(item.icon, color: AppColors.navy),
                      title: Text(item.label, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600)),
                      trailing: item.count > 0 ? _CountBadge(count: item.count) : null,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => _MoreScreen(item: item)));
                      },
                    ),
                ],
              ),
            ),
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
              style: AppTextStyles.body(color: Colors.white, size: 9, weight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _logOut(BuildContext context) async {
    try {
      await context.read<AppState>().logout();
    } catch (_) {
      // Local session is torn down in AppState.logout()'s finally block
      // regardless; still navigate away rather than leaving the user
      // stranded on a screen that thinks it's logged out.
    }
    if (context.mounted) context.go('/admin-login');
  }

  @override
  Widget build(BuildContext context) {
    final adminLevel = context.watch<AppState>().adminLevel;
    final canSeeAdmins = adminLevel?.atLeastModerator ?? false;
    final isSuperAdmin = adminLevel?.isSuperAdmin ?? false;
    final index = _index >= _primaryTabs.length ? 0 : _index;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerSignal: (_) => _resetIdleTimer(),
      child: _usesSidebar(context)
          ? _buildWideScaffold(context, canSeeAdmins, isSuperAdmin, index)
          : _buildScaffold(context, canSeeAdmins, isSuperAdmin, index),
    );
  }

  AppBar _appBar(BuildContext context) => AppBar(
    backgroundColor: AppColors.navy,
    elevation: 0,
    automaticallyImplyLeading: false,
    title: Text('Admin Console', style: AppTextStyles.heading(color: Colors.white, size: 18)),
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: NotificationBell(
          color: Colors.white,
          count: context.watch<AppState>().unreadNotificationCount,
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
  );

  static const _primaryLabels = ['Dashboard', 'Users', 'Vendors', 'Reports'];

  /// The sidebar's groups: every page the phone layout has (the four
  /// primary tabs plus everything under "More"), sorted by what it's for.
  /// Pages this admin's level can't open are simply absent from
  /// [_moreItems], so they (and any group left empty) don't appear.
  List<_NavSection> _sidebarSections(bool canSeeAdmins, bool isSuperAdmin) {
    final pages = {for (final item in _moreItems(canSeeAdmins, isSuperAdmin)) item.label: item};
    _NavEntry? page(String label) {
      final item = pages[label];
      return item == null ? null : _NavEntry(icon: item.icon, label: item.label, count: item.count, page: item);
    }

    const tab = _NavEntry.tab;
    final sections = [
      _NavSection('Overview', [tab(0, Icons.dashboard_outlined, 'Dashboard'), page('Activity Log')]),
      _NavSection('People', [
        tab(1, Icons.people_outline_rounded, 'Users'),
        tab(2, Icons.storefront_outlined, 'Vendors', _pendingVendorsCount),
        page('Admins'),
        page('ID Verifications'),
      ]),
      _NavSection('Listings & marketplace', [page('Properties'), page('Marketplace'), tab(3, Icons.flag_outlined, 'Reports', _openReportsCount)]),
      _NavSection('Money', [page('Payouts & Refunds'), page('Eviction Requests')]),
      _NavSection('Support', [page('Messages'), page('Support Insights'), page('Chat Log')]),
      _NavSection('Platform', [page('Platform Controls')]),
    ];
    return [for (final s in sections) if (s.entries.any((e) => e != null)) s];
  }

  /// Tablets and desktop browsers: every page in a sidebar on the left
  /// (full width with group names on desktop, icons only on tablets, and
  /// either way the admin can expand or collapse it), with the chosen page
  /// beside it. Same pages, badges and permissions as the phone layout.
  Widget _buildWideScaffold(BuildContext context, bool canSeeAdmins, bool isSuperAdmin, int index) {
    final expanded = _sidebarExpanded ?? MediaQuery.sizeOf(context).width >= Breakpoints.expanded;
    final openPage = _openPage;
    final title = openPage?.label ?? _primaryLabels[index];
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _appBar(context),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AdminSidebar(
            sections: _sidebarSections(canSeeAdmins, isSuperAdmin),
            expanded: expanded,
            isSelected: (entry) => entry.page != null ? openPage?.label == entry.label : openPage == null && index == entry.tabIndex,
            onSelect: (entry) => setState(() {
              if (entry.page != null) {
                _openPage = entry.page;
              } else {
                _openPage = null;
                _index = entry.tabIndex!;
              }
            }),
            onToggle: () => setState(() => _sidebarExpanded = !expanded),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
                  child: Text(title, style: AppTextStyles.heading(color: AppColors.navy, size: 20)),
                ),
                Expanded(
                  // The primary tabs stay alive (filters, scroll) while a
                  // sidebar page is open, as with the phone's bottom nav.
                  child: Stack(
                    children: [
                      Offstage(offstage: openPage != null, child: IndexedStack(index: index, children: _primaryTabs)),
                      if (openPage != null) KeyedSubtree(key: ValueKey('admin-page-${openPage.label}'), child: openPage.builder()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, bool canSeeAdmins, bool isSuperAdmin, int index) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: _appBar(context),
      body: IndexedStack(index: index, children: _primaryTabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          if (value == _primaryTabs.length) {
            _openMoreSheet(context, canSeeAdmins, isSuperAdmin);
            return;
          }
          setState(() => _index = value);
        },
        backgroundColor: Colors.white,
        indicatorColor: AppColors.navy.withValues(alpha: 0.1),
        destinations: [
          ..._primaryDestinations,
          NavigationDestination(
            icon: _badgedIcon(Icons.more_horiz_rounded, _moreAttentionTotal(canSeeAdmins, isSuperAdmin)),
            selectedIcon: _badgedIcon(Icons.more_horiz_rounded, _moreAttentionTotal(canSeeAdmins, isSuperAdmin)),
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

/// One group of pages in the wide-screen sidebar. Null entries are pages
/// this admin can't open; they're skipped.
class _NavSection {
  const _NavSection(this.title, this.entries);

  final String title;
  final List<_NavEntry?> entries;
}

/// A sidebar entry: one of the primary tabs ([tabIndex]) or a page that
/// sits under "More" on phones ([page]).
class _NavEntry {
  const _NavEntry({required this.icon, required this.label, this.count = 0, this.tabIndex, this.page});

  const _NavEntry.tab(int index, IconData icon, String label, [int count = 0])
    : this(icon: icon, label: label, count: count, tabIndex: index);

  final IconData icon;
  final String label;
  final int count;
  final int? tabIndex;
  final _MoreItem? page;
}

/// The admin console's left sidebar on tablets and desktop browsers: white,
/// navy icons and labels, the chosen page on a pale navy highlight, dark
/// grey group names (6.2:1 on white) and each page's red count badge.
/// Collapsed, it shows icons only, with the name as a tooltip.
class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.sections,
    required this.expanded,
    required this.isSelected,
    required this.onSelect,
    required this.onToggle,
  });

  final List<_NavSection> sections;
  final bool expanded;
  final bool Function(_NavEntry) isSelected;
  final ValueChanged<_NavEntry> onSelect;
  final VoidCallback onToggle;

  static const _groupColor = Color(0xFF5B6170);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: expanded ? 252 : 76,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0x1A1A2B4C))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
              children: [
                for (final (i, section) in sections.indexed) ...[
                  if (expanded)
                    Padding(
                      padding: EdgeInsets.fromLTRB(12, i == 0 ? 2 : 16, 12, 6),
                      child: Text(
                        section.title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(color: _groupColor, size: 11, weight: FontWeight.w700).copyWith(letterSpacing: 0.6),
                      ),
                    )
                  else if (i > 0)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12), child: Divider(height: 1)),
                  for (final entry in section.entries.whereType<_NavEntry>()) _tile(entry),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Align(
            alignment: expanded ? Alignment.centerRight : Alignment.center,
            child: IconButton(
              onPressed: onToggle,
              tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
              icon: Icon(expanded ? Icons.keyboard_double_arrow_left_rounded : Icons.keyboard_double_arrow_right_rounded, color: AppColors.navy),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(_NavEntry entry) {
    final selected = isSelected(entry);
    final icon = Icon(entry.icon, color: AppColors.navy, size: 22);
    final tile = Material(
      color: selected ? AppColors.navy.withValues(alpha: 0.09) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelect(entry),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0, vertical: 11),
          child: expanded
              ? Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: selected ? FontWeight.w700 : FontWeight.w500),
                      ),
                    ),
                    if (entry.count > 0) _CountBadge(count: entry.count),
                  ],
                )
              : Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      icon,
                      if (entry.count > 0) Positioned(top: -8, right: -12, child: _CountBadge(count: entry.count)),
                    ],
                  ),
                ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: expanded ? tile : Tooltip(message: entry.label, child: tile),
    );
  }
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
        style: AppTextStyles.body(color: Colors.white, size: 11, weight: FontWeight.w800),
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

/// A title/subtitle row with a switch, for the white Account Settings sheet
/// (navy title, grey subtitle on white).
class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 14)),
              Text(subtitle, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
