import 'package:flutter/material.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../dashboard/chat_thread_screen.dart';
import '../dashboard/models/property.dart';
import '../../models/dashboard_theme.dart';
import '../../widgets/empty_state.dart';
import 'models/marketplace_order.dart';
import 'widgets/order_item_thumbnail.dart';

/// Every order a customer has placed on the Marketplace, newest first.
/// Reached from the cart/receipt icon on [MarketplaceHomeScreen]. Lets a
/// customer message a vendor about any item they chose pickup for, and
/// re-order past purchases.
class OrderHistoryScreen extends StatelessWidget {
  const OrderHistoryScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final orders = List.of(customerOrders)..sort((a, b) => b.date.compareTo(a.date));

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
          child: orders.isEmpty
              ? EmptyState(
                  theme: theme,
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message: 'Things you buy on the Marketplace will show up here.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [for (final order in orders) _OrderCard(order: order, theme: theme)],
                ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.theme});

  final MarketplaceOrder order;
  final DashboardTheme theme;

  void _messageVendor(BuildContext context, String vendorName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          theme: theme,
          contactName: vendorName,
          initialMessages: [
            ChatMessage(
              text: "Hi! Your order is ready whenever you'd like to come by for pickup.",
              fromMe: false,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Text(_formatDate(order.date), style: AppTextStyles.body(color: theme.foreground, size: 13.5, weight: FontWeight.w700)),
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
                '₦${formatNaira(order.total)}',
                style: AppTextStyles.body(color: theme.foreground, size: 14, weight: FontWeight.w800),
              ),
            ],
          ),
          if (order.pickupVendors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final vendorName in order.pickupVendors)
                  OutlinedButton.icon(
                    onPressed: () => _messageVendor(context, vendorName),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.accent, width: 1.2),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: Icon(Icons.chat_bubble_outline_rounded, color: theme.accent, size: 16),
                    label: Text(
                      'Message $vendorName',
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

  final OrderItem item;
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
                  '${item.vendorName} · ${item.fulfillment.label}',
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.55), size: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '₦${formatNaira(item.subtotal)}',
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
