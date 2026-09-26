import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/marketplace_api.dart';
import '../../api/models/vendor.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import 'add_product_screen.dart';
import 'widgets/product_thumbnail.dart';
import 'widgets/vendor_bottom_nav.dart';
import 'widgets/vendor_tab_route.dart';

/// The vendor's own product catalog — list what's currently for sale, add
/// a new listing, or remove one.
class VendorProductsScreen extends StatefulWidget {
  const VendorProductsScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorProductsScreen> createState() => _VendorProductsScreenState();
}

class _VendorProductsScreenState extends State<VendorProductsScreen> {
  List<MarketplaceProductApi>? _products;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await context.read<AppState>().marketplaceProducts.mine();
      if (!mounted) return;
      setState(() => _products = products);
    } catch (_) {
      if (!mounted) return;
      setState(() => _products = []);
    }
  }

  void _onNavTap(int index) {
    if (index == 1) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => vendorTabRoute(index, widget.theme)));
  }

  Future<void> _addProduct() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddProductScreen(theme: widget.theme)),
    );
    if (added == true && mounted) _load();
  }

  Future<void> _removeProduct(MarketplaceProductApi product) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().marketplaceProducts.remove(product.id);
      if (!mounted) return;
      setState(() => _products = _products?.where((p) => p.id != product.id).toList());
      messenger.showSnackBar(SnackBar(content: Text('${product.name} removed')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final products = _products;

    return VendorTabScaffold(
      theme: theme,
      currentIndex: 1,
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
                    Text('My Products', style: AppTextStyles.heading(color: theme.foreground, size: 20)),
                    GestureDetector(
                      onTap: _addProduct,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(color: theme.accent, borderRadius: BorderRadius.circular(20)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, color: theme.onAccent, size: 17),
                            const SizedBox(width: 4),
                            Text('Add', style: AppTextStyles.body(color: theme.onAccent, weight: FontWeight.w700, size: 13)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (products == null)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Center(child: CircularProgressIndicator())))
            else if (products.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Center(
                    child: Text(
                      "You haven't listed any products yet",
                      style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 130),
                sliver: SliverList.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) => _VendorProductTile(
                    theme: theme,
                    product: products[index],
                    onRemove: () => _removeProduct(products[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VendorProductTile extends StatelessWidget {
  const _VendorProductTile({required this.theme, required this.product, required this.onRemove});

  final DashboardTheme theme;
  final MarketplaceProductApi product;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: product.isAvailable ? null : Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          ProductThumbnail(
            imageUrl: product.imageUrls.isNotEmpty ? product.imageUrls.first : null,
            icon: Icons.inventory_2_rounded,
            iconColor: theme.onSurface.withValues(alpha: 0.55),
            backgroundColor: theme.onSurface.withValues(alpha: 0.06),
            size: 56,
            borderRadius: 12,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(product.category.label, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12)),
                const SizedBox(height: 2),
                Text(
                  'Item #${product.listingNumber}',
                  style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12, weight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(product.priceLabel, style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700)),
                    if (!product.isAvailable) ...[
                      const SizedBox(width: 8),
                      Text('· Removed', style: AppTextStyles.body(color: Colors.redAccent, size: 11.5, weight: FontWeight.w700)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (product.isAvailable)
            IconButton(
              onPressed: onRemove,
              icon: Icon(Icons.delete_outline_rounded, color: Colors.redAccent.withValues(alpha: 0.8), size: 20),
            ),
        ],
      ),
    );
  }
}
