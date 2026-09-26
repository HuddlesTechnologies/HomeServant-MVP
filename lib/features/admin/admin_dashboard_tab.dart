import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/admin_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await context.read<AppState>().admin.stats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load platform stats.");
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
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        // 220px still meant only 2 (huge) columns on a phone-width
        // viewport — this app is mobile-first, so the previous fix only
        // ever helped on a genuinely wide desktop window. A much smaller
        // cap forces 3+ compact tiles per row even on a narrow screen.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.0,
        ),
        itemCount: cards.length,
        itemBuilder: (context, index) => cards[index],
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
