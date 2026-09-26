import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import 'admin_user_detail_screen.dart';
import 'admin_vendor_detail_screen.dart';

/// Full order detail — reached by tapping an order row (Marketplace tab's
/// Orders segment or the dashboard's activity feed). Read-only: there's no
/// order-level moderation action today, just everything a support
/// conversation about this order would need in one place.
class AdminOrderDetailScreen extends StatefulWidget {
  const AdminOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<AdminOrderDetailScreen> createState() => _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends State<AdminOrderDetailScreen> {
  AdminOrderDetail? _order;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await context.read<AppState>().admin.orderDetail(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load this order.");
    }
  }

  void _openBuyer(String buyerId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserDetailScreen(userId: buyerId)));
  }

  void _openVendor(String vendorId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminVendorDetailScreen(vendorId: vendorId)));
  }

  String _titleCase(String apiValue) {
    final words = apiValue.toLowerCase().split('_');
    return words.map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  Color _statusColor(String status) => switch (status) {
    'COMPLETED' => Colors.green,
    'CANCELLED' => Colors.redAccent,
    _ => Colors.orange,
  };

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Order Details', style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: order == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                order.buyerName ?? order.buyerEmail ?? 'Unknown buyer',
                                style: AppTextStyles.heading(color: AppColors.navy, size: 18),
                              ),
                            ),
                            Text(
                              '₦${formatWithThousandsSeparator(order.total)}',
                              style: AppTextStyles.heading(color: AppColors.navy, size: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _Field('Buyer Email', order.buyerEmail ?? '—'),
                        _Field('Items', '${order.items.length}'),
                        _Field('Placed', formatShortDate(order.createdAt)),
                        if (order.buyerId != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => _openBuyer(order.buyerId!),
                            icon: const Icon(Icons.person_outline_rounded, color: AppColors.navy, size: 18),
                            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.navy)),
                            label: Text("View Buyer's Profile", style: AppTextStyles.button(color: AppColors.navy, size: 13)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Items', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                  const SizedBox(height: 8),
                  for (final item in order.items) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${item.productName} × ${item.quantity}',
                                  style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _Badge(text: _titleCase(item.status), color: _statusColor(item.status)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _Field('Unit Price', '₦${formatWithThousandsSeparator(item.unitPrice)}'),
                          _Field('Subtotal', '₦${formatWithThousandsSeparator(item.unitPrice * item.quantity)}'),
                          _Field('Fulfillment', _titleCase(item.fulfillment)),
                          if (item.trackingNumber != null) _Field('Tracking #', item.trackingNumber!),
                          if (item.shippedAt != null) _Field('Shipped', formatShortDate(item.shippedAt!)),
                          _Field('Vendor', item.vendorName ?? 'Unknown vendor'),
                          if (item.vendorId != null) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _openVendor(item.vendorId!),
                              icon: const Icon(Icons.storefront_outlined, color: AppColors.navy, size: 16),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.navy),
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              ),
                              label: Text("View Vendor's Shop", style: AppTextStyles.button(color: AppColors.navy, size: 12.5)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
      child: Text(text, style: AppTextStyles.body(color: color, size: 11, weight: FontWeight.w700)),
    );
  }
}
