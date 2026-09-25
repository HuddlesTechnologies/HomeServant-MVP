import 'package:flutter/material.dart';
import '../../api/models/marketplace_api.dart';
import '../../api/models/vendor.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/upload_picker.dart';
import 'widgets/marketplace_product_gallery_screen.dart';

class MarketplaceProductDetailScreen extends StatefulWidget {
  const MarketplaceProductDetailScreen({
    super.key,
    required this.product,
    required this.theme,
    required this.cartQuantity,
    required this.onAddToCart,
  });

  final MarketplaceProductApi product;
  final DashboardTheme theme;

  /// How many of this product are currently in the cart — 0 if none.
  final int cartQuantity;

  /// Called with the quantity selected on this screen's stepper when the
  /// shopper taps the add-to-cart button.
  final void Function(MarketplaceProductApi product, int quantity) onAddToCart;

  @override
  State<MarketplaceProductDetailScreen> createState() => _MarketplaceProductDetailScreenState();
}

class _MarketplaceProductDetailScreenState extends State<MarketplaceProductDetailScreen> {
  late int _quantity = widget.cartQuantity > 0 ? widget.cartQuantity : 1;

  void _decrement() {
    if (_quantity <= 1) return;
    setState(() => _quantity--);
  }

  void _increment() {
    if (_quantity >= widget.product.stock) return;
    setState(() => _quantity++);
  }

  bool get _alreadyInCart => widget.cartQuantity > 0 && _quantity == widget.cartQuantity;

  void _openGallery(int index) {
    final images = widget.product.imageUrls.map(imageProviderForPath).toList();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MarketplaceProductGalleryScreen(images: images, initialIndex: index, title: widget.product.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final theme = widget.theme;
    final images = product.imageUrls.map(imageProviderForPath).toList();
    final inStock = product.stock > 0;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ResponsiveCenter(
            maxWidth: 640,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: images.isEmpty ? null : () => _openGallery(0),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: images.isNotEmpty
                            ? Image(image: images.first, fit: BoxFit.cover)
                            : DecoratedBox(
                                decoration: BoxDecoration(color: theme.surface),
                                child: Icon(product.category.icon, color: theme.onSurface.withValues(alpha: 0.5), size: 64),
                              ),
                      ),
                    ),
                  ),
                  if (images.length > 1) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 68,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => GestureDetector(
                          onTap: () => _openGallery(index),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image(image: images[index], width: 68, height: 68, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(product.name, style: AppTextStyles.heading(color: theme.foreground, size: 20)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.vendor?.businessName ?? 'Vendor',
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(color: theme.accent, size: 13.5, weight: FontWeight.w600),
                        ),
                      ),
                      if (product.vendor?.state != null) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.location_on_rounded, size: 13, color: theme.foreground.withValues(alpha: 0.45)),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            product.vendor!.state!,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.55), size: 12.5, weight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (inStock ? Colors.green.shade600 : Colors.redAccent).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          inStock ? '${product.stock} left in stock' : 'Out of stock',
                          style: AppTextStyles.body(
                            color: inStock ? Colors.green.shade700 : Colors.redAccent,
                            size: 11.5,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(product.priceLabel, style: AppTextStyles.heading(color: theme.foreground, size: 24)),
                  if (inStock) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Quantity',
                          style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 13.5, weight: FontWeight.w600),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(24)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: _quantity > 1 ? _decrement : null,
                                icon: Icon(
                                  Icons.remove_rounded,
                                  size: 18,
                                  color: _quantity > 1 ? theme.onSurface.withValues(alpha: 0.8) : theme.onSurface.withValues(alpha: 0.25),
                                ),
                              ),
                              SizedBox(
                                width: 28,
                                child: Text(
                                  '$_quantity',
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.body(color: theme.onSurface, size: 15, weight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                onPressed: _quantity < product.stock ? _increment : null,
                                icon: Icon(
                                  Icons.add_rounded,
                                  size: 18,
                                  color: _quantity < product.stock
                                      ? theme.onSurface.withValues(alpha: 0.8)
                                      : theme.onSurface.withValues(alpha: 0.25),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Description',
                    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.55), size: 13, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.description,
                    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.8), size: 14, weight: FontWeight.w400),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: PillButton(
                      label: !inStock
                          ? 'Out of Stock'
                          : (_alreadyInCart ? 'Already in Cart' : 'Add to Cart'),
                      backgroundColor: !inStock
                          ? theme.accent
                          : (_alreadyInCart ? Colors.green.shade600 : theme.accent),
                      textColor: theme.onAccent,
                      onPressed: inStock ? () => widget.onAddToCart(product, _quantity) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
