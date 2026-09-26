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

/// Escrow/payment-derived progress for a marketplace order item — distinct
/// from the coarser [OrderItemStatus] (PENDING/COMPLETED/CANCELLED on the
/// item itself). Mirrors the held→released escrow lifecycle described in
/// the payment-engine plan (see `Payment.status` server-side): a buyer's
/// payment is held until they confirm receipt, then released to the
/// vendor. The exact backend field/values weren't finalized when this was
/// written, so [fromApi] tries several likely codes and simply returns
/// null for anything unrecognized — callers fall back to [OrderItemStatus]
/// when this is null (see [MarketplaceOrderItemApi.progressLabel]).
enum OrderItemPaymentProgress {
  held,
  released,
  refunded;

  String get label => switch (this) {
    OrderItemPaymentProgress.held => 'Payment Held — Awaiting Your Confirmation',
    OrderItemPaymentProgress.released => 'Completed',
    OrderItemPaymentProgress.refunded => 'Refunded',
  };

  static OrderItemPaymentProgress? fromApi(String? value) {
    switch (value?.toUpperCase()) {
      case 'INITIATED':
      case 'PAID_HELD':
      case 'HELD':
      case 'PAYMENT_HELD':
        return OrderItemPaymentProgress.held;
      case 'RELEASED':
      case 'PAID':
      case 'PAID_OUT':
      case 'COMPLETED':
        return OrderItemPaymentProgress.released;
      case 'REFUNDED':
        return OrderItemPaymentProgress.refunded;
      default:
        return null;
    }
  }
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
    required this.listingNumber,
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

  /// System-assigned sequential number for this listing, unique across
  /// every vendor product ever listed. Always shown to the owning vendor
  /// and to admins; shown to a buyer only once they've paid (see
  /// OrderHistoryScreen and MarketplaceOrderItemApi.productListingNumber).
  final int listingNumber;
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
    listingNumber: json['listingNumber'] as int,
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
    this.productListingNumber,
    this.vendorName,
    this.vendorUserId,
    this.order,
    this.paymentProgressLabel,
    this.paymentProgress,
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

  /// The purchased product's system-assigned listing number — only
  /// meaningful (and only shown to the buyer) once [isPaid] is true, since
  /// a listing number shouldn't surface before payment actually clears.
  final int? productListingNumber;
  final String? vendorName;
  final String? vendorUserId;

  /// Only populated when this item was fetched via the vendor's flattened
  /// order-item view (`GET /marketplace/orders/vendor`), which embeds the
  /// parent order's context inline.
  final MarketplaceOrderContext? order;

  /// A ready-made human-readable progress string, if the server sends one
  /// directly (e.g. "Payment held, awaiting your confirmation").
  final String? paymentProgressLabel;

  /// A recognized payment-status code, if the server sends one instead of
  /// (or alongside) [paymentProgressLabel]. See [OrderItemPaymentProgress].
  final OrderItemPaymentProgress? paymentProgress;

  int get subtotal => unitPrice * quantity;

  /// Best available progress text for this item — prefers a ready-made
  /// label straight from the server, then falls back to a recognized
  /// status code, then finally to the plain item [status] label if
  /// neither newer field is present yet.
  String get progressLabel => paymentProgressLabel ?? paymentProgress?.label ?? status.label;

  /// Whether a "Mark as Received" action makes sense right now. True when
  /// the server explicitly says payment is held, or — until that signal is
  /// wired in everywhere — the item is simply still PENDING with neither
  /// new field present yet (a reasonable default: nothing has completed
  /// or been refunded, so there's nothing wrong with letting the buyer
  /// confirm receipt).
  bool get isPaymentHeld =>
      paymentProgress == OrderItemPaymentProgress.held ||
      (paymentProgress == null && paymentProgressLabel == null && status == OrderItemStatus.pending);

  /// True once this item's payment has actually cleared (held in escrow or
  /// already released to the vendor) — the gate for showing the purchased
  /// product's listing number to the buyer. False for a refunded item,
  /// since the purchase was reversed.
  bool get isPaid => paymentProgress == OrderItemPaymentProgress.held || paymentProgress == OrderItemPaymentProgress.released;

  factory MarketplaceOrderItemApi.fromApi(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final vendor = json['vendor'] as Map<String, dynamic>?;
    final order = json['order'] as Map<String, dynamic>?;
    // Real backend shape: a nested `payment: { status }` (raw Payment
    // status enum — PAID_HELD/RELEASED/REFUNDED/etc, see
    // OrderItemPaymentProgress.fromApi), not a flat top-level field. The
    // other key names below are kept as a defensive fallback only.
    final payment = json['payment'] as Map<String, dynamic>?;
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
      productListingNumber: product?['listingNumber'] as int?,
      vendorName: vendor?['businessName'] as String?,
      vendorUserId: vendor?['userId'] as String?,
      order: order != null ? MarketplaceOrderContext.fromApi(order) : null,
      paymentProgressLabel:
          json['paymentProgressLabel'] as String? ?? json['progressLabel'] as String? ?? json['escrowStatusLabel'] as String?,
      paymentProgress: OrderItemPaymentProgress.fromApi(
        payment?['status'] as String? ?? json['paymentProgress'] as String? ?? json['escrowStatus'] as String? ?? json['paymentStatus'] as String?,
      ),
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

/// Best-effort delivery-tracking snapshot for a delivery-fulfillment order
/// item. The GIG Logistics integration behind `GET
/// /marketplace-orders/items/:id/tracking` is unverified scaffolding as of
/// this writing (no real API contract to build against yet — see the plan
/// doc), and may not exist server-side at all yet, so every field here is
/// optional and parsed defensively from a few likely key spellings; the
/// screen that reads this treats "endpoint 404s / nothing parseable" as
/// "hide the tracking section", not an error.
class DeliveryTrackingApi {
  const DeliveryTrackingApi({this.status, this.trackingNumber, this.carrier, this.estimatedDelivery, this.lastUpdate});

  final String? status;
  final String? trackingNumber;
  final String? carrier;
  final String? estimatedDelivery;
  final String? lastUpdate;

  bool get hasAnyDetail =>
      status != null || trackingNumber != null || carrier != null || estimatedDelivery != null || lastUpdate != null;

  factory DeliveryTrackingApi.fromApi(Map<String, dynamic> json) => DeliveryTrackingApi(
    status: json['status'] as String? ?? json['trackingStatus'] as String?,
    trackingNumber: json['trackingNumber'] as String? ?? json['trackingId'] as String? ?? json['waybillNumber'] as String?,
    carrier: json['carrier'] as String? ?? json['provider'] as String?,
    estimatedDelivery: json['estimatedDelivery'] as String? ?? json['eta'] as String?,
    lastUpdate: json['lastUpdate'] as String? ?? json['statusMessage'] as String? ?? json['note'] as String?,
  );
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
