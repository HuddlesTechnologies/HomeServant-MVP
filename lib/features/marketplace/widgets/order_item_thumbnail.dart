import 'package:flutter/material.dart';
import '../../../api/models/marketplace_api.dart';
import 'product_thumbnail.dart';

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
    return ProductThumbnail(
      imageUrl: item.productImageUrl,
      icon: Icons.inventory_2_rounded,
      iconColor: iconColor,
      backgroundColor: backgroundColor,
      size: size,
      borderRadius: borderRadius,
    );
  }
}
