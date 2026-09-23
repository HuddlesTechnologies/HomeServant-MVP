import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/marketplace_api.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import 'vendor_order_detail_screen.dart';

/// One entry per order the vendor's shop has received, newest first — tap
/// one to see the full order (and, for a delivery item, the customer's
/// contact details). Reached from the bell icon on the vendor dashboard.
class VendorNotificationsScreen extends StatefulWidget {
  const VendorNotificationsScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorNotificationsScreen> createState() => _VendorNotificationsScreenState();
}

class _VendorNotificationsScreenState extends State<VendorNotificationsScreen> {
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

  Future<void> _open(MarketplaceOrderItemApi item) async {
    final appState = context.read<AppState>();
    if (!item.notificationRead) {
      unawaited(appState.marketplaceOrders.markItemRead(item.id));
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VendorOrderDetailScreen(theme: widget.theme, item: item)),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final items = _items;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Notifications', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    "Orders for your shop will show up here.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final order = item.order;
                    final unread = !item.notificationRead;
                    return GestureDetector(
                      onTap: () => _open(item),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(18)),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.accent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.receipt_long_outlined, color: theme.accent, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'New order · ${item.productName}',
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(
                                      color: theme.onSurface,
                                      size: 14,
                                      weight: unread ? FontWeight.w800 : FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${order?.customerName ?? 'Customer'} · ${item.fulfillment.label} · ₦${formatWithThousandsSeparator(item.subtotal)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (unread)
                                  Container(
                                    width: 9,
                                    height: 9,
                                    margin: const EdgeInsets.only(bottom: 6),
                                    decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: item.status.color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    item.status.label,
                                    style: AppTextStyles.body(color: item.status.color, size: 10.5, weight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
