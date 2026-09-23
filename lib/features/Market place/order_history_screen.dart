import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/marketplace_api.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/empty_state.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/order_item_thumbnail.dart';

/// Every order a customer has placed on the Marketplace, newest first.
/// Reached from the cart/receipt icon on [MarketplaceHomeScreen]. Lets a
/// customer message a vendor about any item they chose pickup for, and
/// re-order past purchases.
class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  List<MarketplaceOrderApi>? _orders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await context.read<AppState>().marketplaceOrders.mine();
      if (!mounted) return;
      setState(() => _orders = orders..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _orders = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final orders = _orders;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Order History', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: orders == null
              ? const Center(child: CircularProgressIndicator())
              : orders.isEmpty
              ? EmptyState(
                  theme: theme,
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message: 'Things you buy on the Marketplace will show up here.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [for (final order in orders) _OrderCard(order: order, theme: theme)],
                  ),
                ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.theme});

  final MarketplaceOrderApi order;
  final DashboardTheme theme;

  Future<void> _messageVendor(BuildContext context, MarketplaceOrderItemApi item) async {
    final vendorUserId = item.vendorUserId;
    if (vendorUserId == null) return;
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final thread = await appState.chat.openThread(recipientId: vendorUserId, orderId: item.orderId);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(theme: theme, contactName: item.vendorName ?? 'Vendor', threadId: thread.id),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickupItems = order.pickupItems;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: theme.foreground.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDate(order.createdAt), style: AppTextStyles.body(color: theme.foreground, size: 13.5, weight: FontWeight.w700)),
              Text(order.paymentMethod.label, style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.55), size: 12)),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in order.items) _OrderItemRow(item: item, theme: theme),
          const SizedBox(height: 4),
          Divider(color: theme.foreground.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 13)),
              Text(
                '₦${formatWithThousandsSeparator(order.total)}',
                style: AppTextStyles.body(color: theme.foreground, size: 14, weight: FontWeight.w800),
              ),
            ],
          ),
          if (pickupItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in pickupItems)
                  OutlinedButton.icon(
                    onPressed: () => _messageVendor(context, item),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.accent, width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: Icon(Icons.chat_bubble_outline_rounded, color: theme.accent, size: 16),
                    label: Text(
                      'Message ${item.vendorName ?? 'Vendor'}',
                      style: AppTextStyles.body(color: theme.accent, size: 12.5, weight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item, required this.theme});

  final MarketplaceOrderItemApi item;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          OrderItemThumbnail(item: item, iconColor: theme.foreground.withValues(alpha: 0.5), size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.productName} x${item.quantity}',
                  style: AppTextStyles.body(color: theme.foreground, size: 13.5, weight: FontWeight.w600),
                ),
                Text(
                  '${item.vendorName ?? 'Vendor'} · ${item.fulfillment.label}',
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.55), size: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '₦${formatWithThousandsSeparator(item.subtotal)}',
            style: AppTextStyles.body(color: theme.foreground, size: 13, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';
