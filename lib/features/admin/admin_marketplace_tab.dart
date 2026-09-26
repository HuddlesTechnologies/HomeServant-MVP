import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_permissions.dart';
import 'widgets/admin_search_bar.dart';

enum _MarketplaceView { products, orders }

class AdminMarketplaceTab extends StatefulWidget {
  const AdminMarketplaceTab({super.key, this.initialShowOrders = false});

  /// True to land straight on the Orders segment (e.g. tapping the
  /// dashboard's "Marketplace Orders" tile) instead of the default Products
  /// segment.
  final bool initialShowOrders;

  @override
  State<AdminMarketplaceTab> createState() => _AdminMarketplaceTabState();
}

class _AdminMarketplaceTabState extends State<AdminMarketplaceTab> {
  late _MarketplaceView _view = widget.initialShowOrders ? _MarketplaceView.orders : _MarketplaceView.products;
  List<AdminProduct>? _products;
  List<AdminOrder>? _orders;
  String _search = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (_view == _MarketplaceView.products) {
        final page = await context.read<AppState>().admin.findProducts(search: _search);
        if (!mounted) return;
        setState(() {
          _products = page.items;
          _error = null;
        });
      } else {
        final page = await context.read<AppState>().admin.findOrders();
        if (!mounted) return;
        setState(() {
          _orders = page.items;
          _error = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load that.");
    }
  }

  Future<void> _removeProduct(AdminProduct product) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Remove "${product.name}"?',
      body: "It'll be taken off the Marketplace — past orders referencing it are unaffected. The vendor is emailed the reason you give below.",
      actionLabel: 'Remove',
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.removeProduct(product.id, reason: reason);
      messenger.showSnackBar(SnackBar(content: Text('${product.name} removed')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_MarketplaceView>(
            segments: const [
              ButtonSegment(value: _MarketplaceView.products, label: Text('Products')),
              ButtonSegment(value: _MarketplaceView.orders, label: Text('Orders')),
            ],
            selected: {_view},
            onSelectionChanged: (selection) {
              setState(() => _view = selection.first);
              _load();
            },
          ),
        ),
        if (_view == _MarketplaceView.products)
          AdminSearchBar(
            hint: 'Search products by name or item #',
            onChanged: (value) {
              _search = value;
              _load();
            },
          ),
        Expanded(
          child: _view == _MarketplaceView.products ? _buildProducts() : _buildOrders(),
        ),
      ],
    );
  }

  Widget _buildProducts() {
    final products = _products;
    if (products == null) return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    if (products.isEmpty) return const Center(child: Text('No products found'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final product = products[index];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: adminCardDecoration,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.name, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                      const SizedBox(height: 2),
                      Text(
                        'Item #${product.listingNumber}',
                        style: AppTextStyles.body(color: AppColors.navy, size: 12, weight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${product.vendorName ?? 'Unknown vendor'} · ₦${formatWithThousandsSeparator(product.price)}',
                        style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
                      ),
                      if (!product.isAvailable) ...[
                        const SizedBox(height: 3),
                        Text('Removed', style: AppTextStyles.body(color: Colors.redAccent, size: 11, weight: FontWeight.w700)),
                      ],
                    ],
                  ),
                ),
                if (product.isAvailable && context.canModerate)
                  IconButton(
                    onPressed: () => _removeProduct(product),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrders() {
    final orders = _orders;
    if (orders == null) return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    if (orders.isEmpty) return const Center(child: Text('No orders found'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final order = orders[index];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: adminCardDecoration,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.buyerName ?? order.buyerEmail ?? 'Unknown buyer',
                        style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${order.itemCount} item(s) · ${formatShortDate(order.createdAt)}',
                        style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
                      ),
                    ],
                  ),
                ),
                Text('₦${formatWithThousandsSeparator(order.total)}', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
              ],
            ),
          );
        },
      ),
    );
  }
}
