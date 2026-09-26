import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/marketplace_api.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../dashboard/chat_thread_screen.dart';

/// A customer's conversations with vendors — one per vendor they've
/// bought a pickup item from, since that's the only reason a customer
/// needs to message a vendor in this prototype. Reached from the
/// Marketplace home app bar.
class MarketplaceMessagesScreen extends StatefulWidget {
  const MarketplaceMessagesScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<MarketplaceMessagesScreen> createState() => _MarketplaceMessagesScreenState();
}

class _MarketplaceMessagesScreenState extends State<MarketplaceMessagesScreen> {
  List<MarketplaceOrderItemApi>? _pickupItems;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orders = await context.read<AppState>().marketplaceOrders.mine();
      if (!mounted) return;
      final seen = <String>{};
      final items = <MarketplaceOrderItemApi>[];
      for (final order in orders) {
        for (final item in order.pickupItems) {
          if (seen.add(item.vendorId)) items.add(item);
        }
      }
      setState(() => _pickupItems = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pickupItems = []);
    }
  }

  Future<void> _openChat(MarketplaceOrderItemApi item) async {
    final theme = widget.theme;
    final vendorUserId = item.vendorUserId;
    if (vendorUserId == null) return;
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final thread = await appState.chat.openThread(recipientId: vendorUserId, orderId: item.orderId);
      if (!mounted) return;
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
    final theme = widget.theme;
    final items = _pickupItems;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Messages', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      "You can message a vendor once you've bought a pickup item from them.",
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
                      final vendorName = item.vendorName ?? 'Vendor';
                      return GestureDetector(
                        onTap: () => _openChat(item),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(18)),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: theme.accent.withValues(alpha: 0.25),
                                child: Icon(Icons.storefront_rounded, color: theme.accent),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  vendorName,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w700),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}
