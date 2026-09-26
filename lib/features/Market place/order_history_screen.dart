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
import 'models/order_options.dart';
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
                    children: [for (final order in orders) _OrderCard(order: order, theme: theme, onChanged: _load)],
                  ),
                ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.theme, required this.onChanged});

  final MarketplaceOrderApi order;
  final DashboardTheme theme;

  /// Called after an action on one of this order's items changes server
  /// state (e.g. "Mark as Received") so the parent screen can refetch.
  final Future<void> Function() onChanged;

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
          builder: (_) => ChatThreadScreen(
            theme: theme,
            contactName: item.vendorName ?? 'Vendor',
            threadId: thread.id,
            otherParticipant: thread.otherParticipant,
          ),
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
          for (final item in order.items) _OrderItemRow(item: item, theme: theme, onChanged: onChanged),
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

class _OrderItemRow extends StatefulWidget {
  const _OrderItemRow({required this.item, required this.theme, required this.onChanged});

  final MarketplaceOrderItemApi item;
  final DashboardTheme theme;
  final Future<void> Function() onChanged;

  @override
  State<_OrderItemRow> createState() => _OrderItemRowState();
}

class _OrderItemRowState extends State<_OrderItemRow> {
  DeliveryTrackingApi? _tracking;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    // Only delivery-fulfillment items can have anything to track; this is
    // best-effort GIG-logistics scaffolding that may 404 (not wired up
    // yet) — any failure just leaves [_tracking] null, hiding the section
    // entirely rather than surfacing an error.
    if (widget.item.fulfillment == FulfillmentMethod.delivery) _loadTracking();
  }

  Future<void> _loadTracking() async {
    try {
      final tracking = await context.read<AppState>().marketplaceOrders.tracking(widget.item.id);
      if (!mounted || !tracking.hasAnyDetail) return;
      setState(() => _tracking = tracking);
    } catch (_) {
      // Endpoint unavailable/404/not built yet — leave the section hidden.
    }
  }

  Future<void> _confirmReceived() async {
    setState(() => _confirming = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().marketplaceOrders.confirmReceived(widget.item.id);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Marked as received — payment released to the vendor')));
      await widget.onChanged();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = widget.theme;
    final tracking = _tracking;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _progressColor(item).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.progressLabel,
                        style: AppTextStyles.body(color: _progressColor(item), size: 10.5, weight: FontWeight.w700),
                      ),
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
          if (item.isPaymentHeld) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: SizedBox(
                height: 34,
                child: OutlinedButton(
                  onPressed: _confirming ? null : _confirmReceived,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.accent, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: _confirming
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent),
                        )
                      : Text(
                          'Mark as Received',
                          style: AppTextStyles.body(color: theme.accent, size: 12, weight: FontWeight.w700),
                        ),
                ),
              ),
            ),
          ],
          if (tracking != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.foreground.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_shipping_outlined, size: 14, color: theme.foreground.withValues(alpha: 0.6)),
                        const SizedBox(width: 6),
                        Text(
                          'Track Delivery',
                          style: AppTextStyles.body(color: theme.foreground, size: 11.5, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                    if (tracking.status != null) _TrackingLine(label: 'Status', value: tracking.status!, theme: theme),
                    if (tracking.carrier != null) _TrackingLine(label: 'Carrier', value: tracking.carrier!, theme: theme),
                    if (tracking.trackingNumber != null)
                      _TrackingLine(label: 'Tracking No.', value: tracking.trackingNumber!, theme: theme),
                    if (tracking.estimatedDelivery != null)
                      _TrackingLine(label: 'Estimated', value: tracking.estimatedDelivery!, theme: theme),
                    if (tracking.lastUpdate != null) _TrackingLine(label: 'Update', value: tracking.lastUpdate!, theme: theme),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _progressColor(MarketplaceOrderItemApi item) {
    if (item.paymentProgress == OrderItemPaymentProgress.refunded) return const Color(0xFFE0524B);
    if (item.paymentProgress == OrderItemPaymentProgress.released) return const Color(0xFF2E9E5B);
    if (item.isPaymentHeld) return const Color(0xFFEF9E00);
    return item.status.color;
  }
}

class _TrackingLine extends StatelessWidget {
  const _TrackingLine({required this.label, required this.value, required this.theme});

  final String label;
  final String value;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label: $value',
        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.7), size: 11),
      ),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDate(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';
