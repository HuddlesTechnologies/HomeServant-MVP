import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/admin_models.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'admin_order_detail_screen.dart';
import 'admin_property_detail_screen.dart';
import 'admin_report_detail_screen.dart';
import 'admin_user_detail_screen.dart';
import 'admin_vendor_detail_screen.dart';

/// Every destination a dashboard tile can jump to — handled by
/// [AdminShell] (the only widget that knows how to switch bottom-nav tabs
/// and pre-select a filter), not by this tab itself.
enum AdminDashboardDestination {
  totalUsers,
  tenants,
  landlords,
  vendors,
  pendingVendors,
  activeVendors,
  properties,
  marketplaceOrders,
  deactivatedAccounts,
}

class AdminDashboardTab extends StatefulWidget {
  const AdminDashboardTab({super.key, this.onNavigate});

  /// Null only in contexts where this tab isn't hosted inside AdminShell
  /// (there are none today, but this keeps the widget usable standalone,
  /// e.g. in a test, without requiring a navigation host).
  final void Function(AdminDashboardDestination destination)? onNavigate;

  @override
  State<AdminDashboardTab> createState() => _AdminDashboardTabState();
}

class _AdminDashboardTabState extends State<AdminDashboardTab> {
  AdminStats? _stats;
  String? _error;
  List<ActivityFeedItem>? _activity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final admin = context.read<AppState>().admin;
    try {
      final stats = await admin.stats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load platform stats.");
    }
    try {
      final activity = await admin.activityFeed();
      if (!mounted) return;
      setState(() => _activity = activity);
    } catch (_) {
      // Best-effort — the stat tiles above are the dashboard's core job;
      // a failed feed load just leaves that section showing its own
      // "couldn't load" state rather than blocking the whole screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null) {
      return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    }
    final onNavigate = widget.onNavigate;
    final cards = [
      _StatCard(
        label: 'Total Users',
        value: '${stats.totalUsers}',
        icon: Icons.people_rounded,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.totalUsers),
      ),
      _StatCard(
        label: 'Tenants',
        value: '${stats.tenants}',
        icon: Icons.person_outline_rounded,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.tenants),
      ),
      _StatCard(
        label: 'Landlords',
        value: '${stats.landlords}',
        icon: Icons.home_work_outlined,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.landlords),
      ),
      _StatCard(
        label: 'Vendors',
        value: '${stats.vendors}',
        icon: Icons.storefront_outlined,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.vendors),
      ),
      _StatCard(
        label: 'Pending Vendor Reviews',
        value: '${stats.pendingVendors}',
        icon: Icons.pending_actions_rounded,
        highlight: stats.pendingVendors > 0,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.pendingVendors),
      ),
      _StatCard(
        label: 'Active Vendors',
        value: '${stats.activeVendors}',
        icon: Icons.verified_outlined,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.activeVendors),
      ),
      _StatCard(
        label: 'Properties',
        value: '${stats.properties}',
        icon: Icons.apartment_rounded,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.properties),
      ),
      // No admin Bookings screen exists yet — this tile stays a plain
      // read-only count until one is built.
      _StatCard(label: 'Bookings', value: '${stats.bookings}', icon: Icons.event_available_rounded),
      _StatCard(
        label: 'Marketplace Orders',
        value: '${stats.marketplaceOrders}',
        icon: Icons.shopping_bag_rounded,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.marketplaceOrders),
      ),
      _StatCard(
        label: 'Deactivated Accounts',
        value: '${stats.deactivatedAccounts}',
        icon: Icons.pause_circle_outline_rounded,
        onTap: onNavigate == null ? null : () => onNavigate(AdminDashboardDestination.deactivatedAccounts),
      ),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            // 220px still meant only 2 (huge) columns on a phone-width
            // viewport — this app is mobile-first, so the previous fix only
            // ever helped on a genuinely wide desktop window. A much smaller
            // cap forces 3+ compact tiles per row even on a narrow screen.
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 130,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              delegate: SliverChildBuilderDelegate((context, index) => cards[index], childCount: cards.length),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverToBoxAdapter(child: _ActivityFeedSection(items: _activity)),
          ),
        ],
      ),
    );
  }
}

/// "What's happening on the platform" — recent signups, listings, vendor
/// applications, orders, and reports, merged and sorted by time. See
/// AdminRepository.activityFeed / AdminService.activityFeed. Every row is
/// tappable — it opens the same detail screen its own tab's list row would
/// (user profile, listing, vendor shop, order, or report), using
/// [ActivityFeedItem.entityId].
class _ActivityFeedSection extends StatelessWidget {
  const _ActivityFeedSection({required this.items});

  final List<ActivityFeedItem>? items;

  IconData _iconFor(ActivityFeedType type) => switch (type) {
    ActivityFeedType.userSignup => Icons.person_add_alt_1_rounded,
    ActivityFeedType.propertyListed => Icons.apartment_rounded,
    ActivityFeedType.vendorApplication => Icons.storefront_outlined,
    ActivityFeedType.marketplaceOrder => Icons.shopping_bag_outlined,
    ActivityFeedType.reportFiled => Icons.flag_outlined,
  };

  Color _colorFor(ActivityFeedType type) => type == ActivityFeedType.reportFiled ? Colors.redAccent : AppColors.navy;

  void _open(BuildContext context, ActivityFeedItem item) {
    final screen = switch (item.type) {
      ActivityFeedType.userSignup => AdminUserDetailScreen(userId: item.entityId),
      ActivityFeedType.propertyListed => AdminPropertyDetailScreen(propertyId: item.entityId),
      ActivityFeedType.vendorApplication => AdminVendorDetailScreen(vendorId: item.entityId),
      ActivityFeedType.marketplaceOrder => AdminOrderDetailScreen(orderId: item.entityId),
      ActivityFeedType.reportFiled => AdminReportDetailScreen(reportId: item.entityId),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final items = this.items;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recent Activity', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 15)),
          const SizedBox(height: 12),
          if (items == null)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (items.isEmpty)
            Text('No recent activity', style: AppTextStyles.body(color: AppColors.hintGrey, size: 13))
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 18),
              InkWell(
                onTap: () => _open(context, items[i]),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_iconFor(items[i].type), color: _colorFor(items[i].type), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          items[i].summary,
                          style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRelativeTime(items[i].createdAt),
                        style: AppTextStyles.body(color: AppColors.hintGrey, size: 11),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.hintGrey, size: 16),
                    ],
                  ),
                ),
              ),
            ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, this.highlight = false, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: highlight ? Border.all(color: Colors.orange, width: 1.2) : null,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: highlight ? Colors.orange : AppColors.navy, size: 16),
              Text(
                value,
                style: AppTextStyles.heading(color: AppColors.navy, size: 17),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: AppTextStyles.body(color: AppColors.hintGrey, size: 10),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
