import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/marketplace_api.dart';
import '../../api/models/vendor.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/upload_picker.dart';
import 'models/order_options.dart';
import 'vendor_messages_screen.dart';
import 'vendor_notifications_screen.dart';
import 'vendor_order_detail_screen.dart';
import 'vendor_products_screen.dart';
import 'vendor_profile_screen.dart';
import 'widgets/vendor_bottom_nav.dart';

/// The signed-in vendor's home base — a snapshot of their shop's products,
/// orders and revenue. Reached after [VendorLoginScreen]; the bottom nav
/// hands off to the separate [VendorProductsScreen] and
/// [VendorProfileScreen] screens.
class VendorDashboardScreen extends StatefulWidget {
  const VendorDashboardScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends State<VendorDashboardScreen> {
  VendorProfile? _vendor;
  List<MarketplaceProductApi>? _products;
  List<MarketplaceOrderItemApi>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    try {
      final results = await Future.wait([
        appState.vendors.me(),
        appState.marketplaceProducts.mine(),
        appState.marketplaceOrders.forVendor(),
      ]);
      if (!mounted) return;
      setState(() {
        _vendor = results[0] as VendorProfile;
        _products = results[1] as List<MarketplaceProductApi>;
        _items = results[2] as List<MarketplaceOrderItemApi>;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load your shop — pull to try again.");
    }
  }

  void _onNavTap(int index) {
    if (index == 0) return;
    final screen = index == 1 ? VendorProductsScreen(theme: widget.theme) : VendorProfileScreen(theme: widget.theme);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VendorNotificationsScreen(theme: widget.theme)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final vendor = _vendor;
    final products = _products;
    final items = _items;

    if (vendor == null || products == null || items == null) {
      return VendorTabScaffold(
        theme: theme,
        currentIndex: 0,
        onNavTap: _onNavTap,
        body: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6))),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    final revenue = items.where((i) => i.status != OrderItemStatus.cancelled).fold<int>(0, (sum, i) => sum + i.subtotal);
    final unreadCount = items.where((i) => !i.notificationRead).length;
    final recent = List.of(items)..sort((a, b) => (b.order?.createdAt ?? DateTime(0)).compareTo(a.order?.createdAt ?? DateTime(0)));

    return VendorTabScaffold(
      theme: theme,
      currentIndex: 0,
      onNavTap: _onNavTap,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back,', style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 13)),
                          Text(
                            vendor.businessName,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.heading(color: theme.foreground, size: 20),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconButton(
                              onPressed: _openNotifications,
                              icon: Icon(Icons.notifications_none_rounded, color: theme.foreground),
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                  child: Text(
                                    '$unreadCount',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.body(color: theme.onAccent, size: 9, weight: FontWeight.w800),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => VendorMessagesScreen(theme: theme)),
                          ),
                          icon: Icon(Icons.chat_bubble_outline_rounded, color: theme.foreground),
                        ),
                        const SizedBox(width: 4),
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: theme.accent.withValues(alpha: 0.15),
                          backgroundImage: vendor.logoUrl != null ? imageProviderForPath(vendor.logoUrl!) : null,
                          child: vendor.logoUrl == null
                              ? Icon(Icons.storefront_rounded, color: theme.accent, size: 22)
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (vendor.status != VendorApplicationStatus.approved)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _VendorStatusBanner(theme: theme, vendor: vendor),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Row(
                  children: [
                    _StatCard(theme: theme, label: 'Products', value: '${products.length}'),
                    const SizedBox(width: 12),
                    _StatCard(theme: theme, label: 'Orders', value: '${items.length}'),
                    const SizedBox(width: 12),
                    _StatCard(theme: theme, label: 'Revenue', value: '₦${formatWithThousandsSeparator(revenue)}', small: true),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                child: Text('Recent Orders', style: AppTextStyles.heading(color: theme.foreground, size: 17)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 130),
              sliver: recent.isEmpty
                  ? SliverToBoxAdapter(
                      child: Text(
                        'Orders for your shop will show up here.',
                        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.55), size: 13),
                      ),
                    )
                  : SliverList.builder(
                      itemCount: recent.length,
                      itemBuilder: (context, index) {
                        final item = recent[index];
                        return GestureDetector(
                          onTap: () async {
                            if (!item.notificationRead) {
                              await context.read<AppState>().marketplaceOrders.markItemRead(item.id);
                            }
                            if (!mounted) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => VendorOrderDetailScreen(theme: theme, item: item)),
                            );
                            _load();
                          },
                          child: _OrderTile(theme: theme, item: item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown above the stats row while a vendor's shop hasn't cleared admin
/// review yet — their products still exist and can be managed, but stay
/// hidden from the public Marketplace feed until approved (see
/// backend/src/marketplace-products/marketplace-products.service.ts).
class _VendorStatusBanner extends StatelessWidget {
  const _VendorStatusBanner({required this.theme, required this.vendor});

  final DashboardTheme theme;
  final VendorProfile vendor;

  @override
  Widget build(BuildContext context) {
    final rejected = vendor.status == VendorApplicationStatus.rejected;
    final color = rejected ? Colors.redAccent : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(rejected ? Icons.error_outline_rounded : Icons.pending_actions_rounded, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rejected ? 'Application not approved' : 'Your shop is under review',
                  style: AppTextStyles.body(color: color, weight: FontWeight.w700, size: 13.5),
                ),
                const SizedBox(height: 3),
                Text(
                  rejected
                      ? (vendor.rejectionReason ?? 'Update your shop details from Shop Profile and it will be reviewed again.')
                      : "Your products aren't visible to shoppers yet — you can still set up your shop while you wait.",
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.7), size: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.theme, required this.label, required this.value, this.small = false});

  final DashboardTheme theme;
  final String label;
  final String value;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.heading(color: theme.onSurface, size: small ? 15 : 20),
            ),
            const SizedBox(height: 4),
            Text(label, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12)),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.theme, required this.item});

  final DashboardTheme theme;
  final MarketplaceOrderItemApi item;

  @override
  Widget build(BuildContext context) {
    final order = item.order;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName, style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  '${order?.customerName ?? 'Customer'} · ${order != null ? _formatDate(order.createdAt) : ''}',
                  style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₦${formatWithThousandsSeparator(item.subtotal)}',
                style: AppTextStyles.body(color: theme.onSurface, size: 13.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: item.status.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Text(item.status.label, style: AppTextStyles.body(color: item.status.color, size: 10.5, weight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${date.day} ${months[date.month - 1]}';
}
