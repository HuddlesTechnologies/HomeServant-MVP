import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/marketplace_api.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../features/Market place/models/order_options.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/order_status_badge.dart';
import 'vendor_order_detail_screen.dart';

/// A ledger view of everything the vendor has sold — the same underlying
/// order items as Notifications, framed for tracking payouts rather than
/// spotting new orders. Reached from the Shop Profile screen.
class VendorTransactionsScreen extends StatefulWidget {
  const VendorTransactionsScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorTransactionsScreen> createState() => _VendorTransactionsScreenState();
}

class _VendorTransactionsScreenState extends State<VendorTransactionsScreen> {
  List<MarketplaceOrderItemApi>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await context.read<AppState>().marketplaceOrders.forVendor();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final items = _items;
    final totalEarned = (items ?? [])
        .where((i) => i.status == OrderItemStatus.completed)
        .fold<int>(0, (sum, i) => sum + i.subtotal);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Transaction History', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Your sales will show up here once you get an order.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total from completed orders',
                            style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 13),
                          ),
                          Text(
                            '₦${formatWithThousandsSeparator(totalEarned)}',
                            style: AppTextStyles.heading(color: theme.onSurface, size: 17),
                          ),
                        ],
                      ),
                    ),
                    for (final item in items)
                      GestureDetector(
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => VendorOrderDetailScreen(theme: theme, item: item)),
                          );
                          if (mounted) _load();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productName,
                                      style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${item.order?.customerName ?? 'Customer'} · ${item.order?.paymentMethod.label ?? ''}',
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
                                  OrderStatusBadge(status: item.status),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
