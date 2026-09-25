import 'package:flutter/material.dart';
import '../core/theme/app_text_styles.dart';
import '../features/Market place/models/order_options.dart';

/// The small colored status pill for an [OrderItemStatus] — its color and
/// label come straight off the enum. Reused by every vendor screen that
/// lists or details an order item, so they all render the exact same pill.
/// The two size presets seen across those screens are the list-row default
/// (used in dashboard/notifications/messages/transactions lists) and the
/// slightly larger one used on the order detail header.
class OrderStatusBadge extends StatelessWidget {
  const OrderStatusBadge({
    super.key,
    required this.status,
    this.horizontalPadding = 8,
    this.verticalPadding = 3,
    this.borderRadius = 10,
    this.fontSize = 10.5,
  });

  final OrderItemStatus status;
  final double horizontalPadding;
  final double verticalPadding;
  final double borderRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
      decoration: BoxDecoration(color: status.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(borderRadius)),
      child: Text(status.label, style: AppTextStyles.body(color: status.color, size: fontSize, weight: FontWeight.w700)),
    );
  }
}
