import 'package:flutter/material.dart';
import '../../../api/models/marketplace_api.dart';

/// Shows the ordered product's own photo — the backend embeds it directly
/// on the order-item response, no separate catalog lookup needed. Falls
/// back to a generic icon if the product has none (or was since removed).
class OrderItemThumbnail extends StatelessWidget {
  const OrderItemThumbnail({
    super.key,
    required this.item,
    required this.iconColor,
    this.backgroundColor,
    this.size = 44,
    this.borderRadius = 12,
  });

  final MarketplaceOrderItemApi item;
  final Color iconColor;
  final Color? backgroundColor;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.productImageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        width: size,
        height: size,
        color: backgroundColor ?? iconColor.withValues(alpha: 0.12),
        alignment: Alignment.center,
        child: imageUrl == null
            ? Icon(Icons.inventory_2_rounded, color: iconColor, size: size * 0.5)
            : Image.network(imageUrl, fit: BoxFit.cover, width: size, height: size),
      ),
    );
  }
}
