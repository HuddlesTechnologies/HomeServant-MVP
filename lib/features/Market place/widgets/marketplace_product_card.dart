import 'package:flutter/material.dart';
import '../../../api/models/marketplace_api.dart';
import '../../../api/models/vendor.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/dashboard_theme.dart';
import '../../../widgets/upload_picker.dart';

class MarketplaceProductCard extends StatefulWidget {
  const MarketplaceProductCard({
    super.key,
    required this.product,
    required this.theme,
    required this.cartQuantity,
    required this.onAddToCart,
    required this.onOpen,
  });

  final MarketplaceProductApi product;
  final DashboardTheme theme;

  /// How many of this product are currently in the cart — 0 if none. Drives
  /// the stepper's starting value and stays in sync with it, so the same
  /// number is visible both while picking a quantity and after it's been
  /// added to the cart.
  final int cartQuantity;

  /// Called with the quantity currently selected on the stepper when the
  /// shopper taps the add-to-cart button.
  final ValueChanged<int> onAddToCart;

  final VoidCallback onOpen;

  @override
  State<MarketplaceProductCard> createState() => _MarketplaceProductCardState();
}

class _MarketplaceProductCardState extends State<MarketplaceProductCard> {
  late int _quantity = widget.cartQuantity > 0 ? widget.cartQuantity : 1;

  @override
  void didUpdateWidget(covariant MarketplaceProductCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Resync when the cart changes from elsewhere (checkout clearing it,
    // or the cart sheet's own remove button) rather than from this card.
    if (widget.cartQuantity != oldWidget.cartQuantity) {
      setState(() => _quantity = widget.cartQuantity > 0 ? widget.cartQuantity : 1);
    }
  }

  void _decrement() {
    if (_quantity <= 1) return;
    setState(() => _quantity--);
  }

  void _increment() {
    if (_quantity >= widget.product.stock) return;
    setState(() => _quantity++);
  }

  bool get _alreadyInCart => widget.cartQuantity > 0 && _quantity == widget.cartQuantity;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final product = widget.product;
    final images = product.imageUrls;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onOpen,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 11,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: images.isNotEmpty
                    ? Image(image: imageProviderForPath(images.first), fit: BoxFit.cover)
                    : DecoratedBox(
                        decoration: BoxDecoration(color: theme.onSurface.withValues(alpha: 0.06)),
                        child: Icon(product.category.icon, color: theme.onSurface.withValues(alpha: 0.55), size: 36),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              product.vendor?.businessName ?? 'Vendor',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  product.priceLabel,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: theme.onSurface, size: 14.5, weight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 7,
                  color: product.stock > 0 ? Colors.green.shade600 : Colors.redAccent,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    product.stock > 0 ? '${product.stock} in stock' : 'Out of stock',
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(
                      color: product.stock > 0 ? Colors.green.shade700 : Colors.redAccent,
                      size: 11,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: theme.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StepperButton(theme: theme, icon: Icons.remove_rounded, onTap: _quantity > 1 ? _decrement : null),
                      SizedBox(
                        width: 22,
                        child: Text(
                          '$_quantity',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(color: theme.onSurface, size: 12.5, weight: FontWeight.w700),
                        ),
                      ),
                      _StepperButton(
                        theme: theme,
                        icon: Icons.add_rounded,
                        onTap: _quantity < product.stock ? _increment : null,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: product.stock > 0 ? () => widget.onAddToCart(_quantity) : null,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: product.stock <= 0
                          ? theme.onSurface.withValues(alpha: 0.15)
                          : (_alreadyInCart ? Colors.green.shade600 : theme.accent),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _alreadyInCart ? Icons.check_rounded : Icons.add_shopping_cart_rounded,
                      color: product.stock > 0 ? theme.onAccent : theme.onSurface.withValues(alpha: 0.4),
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.cartQuantity > 0) ...[
              const SizedBox(height: 6),
              Text(
                'In cart: ${widget.cartQuantity}',
                style: AppTextStyles.body(color: theme.accent, size: 11, weight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.theme, required this.icon, required this.onTap});

  final DashboardTheme theme;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Icon(icon, size: 14, color: enabled ? theme.onSurface.withValues(alpha: 0.8) : theme.onSurface.withValues(alpha: 0.25)),
      ),
    );
  }
}
