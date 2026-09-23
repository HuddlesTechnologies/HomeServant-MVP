import '../../core/thousands_separator.dart';
import '../../features/Market place/models/order_options.dart';
import 'vendor.dart';

extension FulfillmentMethodApi on FulfillmentMethod {
  String get apiValue => this == FulfillmentMethod.delivery ? 'DELIVERY' : 'PICKUP';

  static FulfillmentMethod fromApi(String value) => value == 'DELIVERY' ? FulfillmentMethod.delivery : FulfillmentMethod.pickup;
}

extension PaymentMethodApi on PaymentMethod {
  String get apiValue => this == PaymentMethod.card ? 'CARD' : 'BANK_TRANSFER';

  static PaymentMethod fromApi(String value) => value == 'CARD' ? PaymentMethod.card : PaymentMethod.bankTransfer;
}

extension OrderItemStatusApi on OrderItemStatus {
  String get apiValue => switch (this) {
    OrderItemStatus.pending => 'PENDING',
    OrderItemStatus.completed => 'COMPLETED',
    OrderItemStatus.cancelled => 'CANCELLED',
  };

  static OrderItemStatus fromApi(String value) => switch (value) {
    'COMPLETED' => OrderItemStatus.completed,
    'CANCELLED' => OrderItemStatus.cancelled,
    _ => OrderItemStatus.pending,
  };
}

/// A vendor summary embedded on a product/order-item response — just
/// enough to render "sold by X" without a separate lookup.
class VendorSummary {
  const VendorSummary({required this.id, required this.businessName, this.userId, this.state, this.logoUrl});

  final String id;
  final String businessName;
  final String? userId;
  final String? state;
  final String? logoUrl;

  factory VendorSummary.fromApi(Map<String, dynamic> json) => VendorSummary(
    id: json['id'] as String,
    businessName: json['businessName'] as String,
    userId: json['userId'] as String?,
    state: json['state'] as String?,
    logoUrl: json['logoUrl'] as String?,
  );
}

class MarketplaceProductApi {
  const MarketplaceProductApi({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.description,
    required this.price,
    required this.stock,
    required this.category,
    required this.imageUrls,
    required this.fulfillmentOptions,
    required this.isAvailable,
    this.videoUrl,
    this.vendor,
  });

  final String id;
  final String vendorId;
  final String name;
  final String description;
  final int price;
  final int stock;
  final MarketplaceCategory category;
  final List<String> imageUrls;
  final String? videoUrl;
  final Set<FulfillmentMethod> fulfillmentOptions;
  final bool isAvailable;
  final VendorSummary? vendor;

  String get priceLabel => '₦${formatWithThousandsSeparator(price)}';

  factory MarketplaceProductApi.fromApi(Map<String, dynamic> json) => MarketplaceProductApi(
    id: json['id'] as String,
    vendorId: json['vendorId'] as String,
    name: json['name'] as String,
    description: json['description'] as String,
    price: json['price'] as int,
    stock: json['stock'] as int,
    category: MarketplaceCategoryApi.fromApi(json['category'] as String),
    imageUrls: (json['imageUrls'] as List).cast<String>(),
    videoUrl: json['videoUrl'] as String?,
    fulfillmentOptions: (json['fulfillmentOptions'] as List).cast<String>().map(FulfillmentMethodApi.fromApi).toSet(),
    isAvailable: json['isAvailable'] as bool? ?? true,
    vendor: json['vendor'] != null ? VendorSummary.fromApi(json['vendor'] as Map<String, dynamic>) : null,
  );
}

class MarketplaceOrderItemApi {
  const MarketplaceOrderItemApi({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.vendorId,
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.fulfillment,
    required this.status,
    required this.notificationRead,
    this.productImageUrl,
    this.vendorName,
    this.vendorUserId,
    this.order,
  });

  final String id;
  final String orderId;
  final String productId;
  final String vendorId;
  final String productName;
  final int unitPrice;
  final int quantity;
  final FulfillmentMethod fulfillment;
  final OrderItemStatus status;
  final bool notificationRead;
  final String? productImageUrl;
  final String? vendorName;
  final String? vendorUserId;

  /// Only populated when this item was fetched via the vendor's flattened
  /// order-item view (`GET /marketplace/orders/vendor`), which embeds the
  /// parent order's context inline.
  final MarketplaceOrderContext? order;

  int get subtotal => unitPrice * quantity;

  factory MarketplaceOrderItemApi.fromApi(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final vendor = json['vendor'] as Map<String, dynamic>?;
    final order = json['order'] as Map<String, dynamic>?;
    return MarketplaceOrderItemApi(
      id: json['id'] as String,
      orderId: json['orderId'] as String,
      productId: json['productId'] as String,
      vendorId: json['vendorId'] as String,
      productName: json['productName'] as String,
      unitPrice: json['unitPrice'] as int,
      quantity: json['quantity'] as int,
      fulfillment: FulfillmentMethodApi.fromApi(json['fulfillment'] as String),
      status: OrderItemStatusApi.fromApi(json['status'] as String),
      notificationRead: json['notificationRead'] as bool? ?? false,
      productImageUrl: (product?['imageUrls'] as List?)?.cast<String>().firstOrNull,
      vendorName: vendor?['businessName'] as String?,
      vendorUserId: vendor?['userId'] as String?,
      order: order != null ? MarketplaceOrderContext.fromApi(order) : null,
    );
  }
}

/// The parent order's context, as embedded on a vendor's flattened
/// order-item view — enough to show/contact the buyer without a second
/// request.
class MarketplaceOrderContext {
  const MarketplaceOrderContext({
    required this.id,
    required this.createdAt,
    required this.paymentMethod,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.buyerId,
  });

  final String id;
  final DateTime createdAt;
  final PaymentMethod paymentMethod;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String buyerId;

  factory MarketplaceOrderContext.fromApi(Map<String, dynamic> json) => MarketplaceOrderContext(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    paymentMethod: PaymentMethodApi.fromApi(json['paymentMethod'] as String),
    customerName: json['customerName'] as String,
    customerPhone: json['customerPhone'] as String,
    customerAddress: json['customerAddress'] as String,
    buyerId: json['buyerId'] as String,
  );
}

class MarketplaceOrderApi {
  const MarketplaceOrderApi({
    required this.id,
    required this.createdAt,
    required this.paymentMethod,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.items,
  });

  final String id;
  final DateTime createdAt;
  final PaymentMethod paymentMethod;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final List<MarketplaceOrderItemApi> items;

  int get total => items.fold(0, (sum, item) => sum + item.subtotal);

  /// Distinct vendors among this order's pickup-fulfillment items — used
  /// to decide who's messageable from order history.
  List<MarketplaceOrderItemApi> get pickupItems {
    final seen = <String>{};
    return items
        .where((i) => i.fulfillment == FulfillmentMethod.pickup)
        .where((i) => seen.add(i.vendorId))
        .toList();
  }

  factory MarketplaceOrderApi.fromApi(Map<String, dynamic> json) => MarketplaceOrderApi(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    paymentMethod: PaymentMethodApi.fromApi(json['paymentMethod'] as String),
    customerName: json['customerName'] as String,
    customerPhone: json['customerPhone'] as String,
    customerAddress: json['customerAddress'] as String,
    items: (json['items'] as List).cast<Map<String, dynamic>>().map(MarketplaceOrderItemApi.fromApi).toList(),
  );
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
