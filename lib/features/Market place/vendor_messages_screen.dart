import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/marketplace_api.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/order_status_badge.dart';
import '../dashboard/chat_thread_screen.dart';
import 'models/order_options.dart';

/// The vendor's conversations with customers — one per pickup order, since
/// that's the only case a vendor needs to coordinate with a customer in
/// this prototype. Reached from the vendor dashboard's app bar.
class VendorMessagesScreen extends StatefulWidget {
  const VendorMessagesScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorMessagesScreen> createState() => _VendorMessagesScreenState();
}

class _VendorMessagesScreenState extends State<VendorMessagesScreen> {
  DashboardTheme get theme => widget.theme;
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
      setState(() => _items = items.where((i) => i.fulfillment == FulfillmentMethod.pickup).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _items = []);
    }
  }

  List<MarketplaceOrderItemApi> get _activeOrders =>
      (_items ?? []).where((i) => i.status == OrderItemStatus.pending).toList();

  /// Completed and cancelled orders, grouped into their own section below the
  /// active ones and sorted so completed orders lead ahead of cancelled ones.
  List<MarketplaceOrderItemApi> get _pastOrders =>
      (_items ?? []).where((i) => i.status != OrderItemStatus.pending).toList()
        ..sort((a, b) => a.status.index.compareTo(b.status.index));

  Future<void> _openChat(MarketplaceOrderItemApi item) async {
    final order = item.order;
    if (order == null) return;
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final thread = await appState.chat.openThread(recipientId: order.buyerId, orderId: item.orderId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            theme: theme,
            contactName: order.customerName,
            threadId: thread.id,
            orderItem: item,
          ),
        ),
      );
      if (mounted) _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final activeOrders = _activeOrders;
    final pastOrders = _pastOrders;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Messages', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : activeOrders.isEmpty && pastOrders.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    "You can message a customer once they've bought a pickup item from you.",
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
                    ...activeOrders.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _MessageRow(theme: theme, item: item, onTap: () => _openChat(item)),
                      ),
                    ),
                    if (pastOrders.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.only(top: activeOrders.isEmpty ? 0 : 16, bottom: 8),
                        child: Text('Completed & Cancelled', style: AppTextStyles.heading(color: theme.foreground, size: 15)),
                      ),
                      ...pastOrders.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _MessageRow(theme: theme, item: item, onTap: () => _openChat(item), showStatus: true),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.theme, required this.item, required this.onTap, this.showStatus = false});

  final DashboardTheme theme;
  final MarketplaceOrderItemApi item;
  final VoidCallback onTap;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.accent.withValues(alpha: 0.25),
              child: Icon(Icons.person, color: theme.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.order?.customerName ?? 'Customer',
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.productName,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 12.5),
                  ),
                ],
              ),
            ),
            if (showStatus) ...[
              OrderStatusBadge(status: item.status),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}
