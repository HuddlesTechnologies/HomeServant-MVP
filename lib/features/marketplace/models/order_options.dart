import 'package:flutter/material.dart';

/// How a marketplace order is fulfilled — shared by [MarketplaceProduct]
/// (what a vendor supports for that item), the customer cart (what a
/// shopper picks per item), and [VendorOrder] (what the customer chose).
enum FulfillmentMethod {
  delivery,
  pickup;

  String get label => this == FulfillmentMethod.delivery ? 'Delivery' : 'Pickup';
  IconData get icon => this == FulfillmentMethod.delivery ? Icons.local_shipping_outlined : Icons.storefront_outlined;
}

/// How a customer pays at checkout. Shared by the payment modal and the
/// vendor's order detail screen, which shows what was actually used.
enum PaymentMethod {
  card,
  bankTransfer;

  String get label => switch (this) {
    PaymentMethod.card => 'Debit/Credit Card',
    PaymentMethod.bankTransfer => 'Bank Transfer',
  };

  IconData get icon => switch (this) {
    PaymentMethod.card => Icons.credit_card_rounded,
    PaymentMethod.bankTransfer => Icons.account_balance_outlined,
  };
}

/// Fulfillment state of one [OrderItem] — tracked per item (not per whole
/// order) since a cart can span several vendors, each fulfilling their own
/// items independently.
enum OrderItemStatus {
  pending,
  completed,
  cancelled;

  String get label => switch (this) {
    OrderItemStatus.pending => 'Pending',
    OrderItemStatus.completed => 'Completed',
    OrderItemStatus.cancelled => 'Cancelled',
  };

  Color get color => switch (this) {
    OrderItemStatus.pending => const Color(0xFFEF9E00),
    OrderItemStatus.completed => const Color(0xFF2E9E5B),
    OrderItemStatus.cancelled => const Color(0xFFE0524B),
  };
}
