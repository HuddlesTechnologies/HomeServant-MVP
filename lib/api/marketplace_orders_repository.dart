import '../features/Market place/models/order_options.dart';
import 'api_client.dart';
import 'models/marketplace_api.dart';

class MarketplaceOrderItemInput {
  const MarketplaceOrderItemInput({required this.productId, required this.quantity, required this.fulfillment});

  final String productId;
  final int quantity;
  final FulfillmentMethod fulfillment;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantity': quantity,
    'fulfillment': fulfillment.apiValue,
  };
}

class MarketplaceOrdersRepository {
  MarketplaceOrdersRepository(this._client);

  final ApiClient _client;

  Future<MarketplaceOrderApi> create({
    required List<MarketplaceOrderItemInput> items,
    required PaymentMethod paymentMethod,
  }) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/marketplace/orders',
        data: {'items': items.map((i) => i.toJson()).toList(), 'paymentMethod': paymentMethod.apiValue},
      );
      return MarketplaceOrderApi.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<List<MarketplaceOrderApi>> mine() {
    return _client.call(() async {
      final response = await _client.dio.get('/marketplace/orders/mine');
      return (response.data as List).cast<Map<String, dynamic>>().map(MarketplaceOrderApi.fromApi).toList();
    });
  }

  Future<List<MarketplaceOrderItemApi>> forVendor() {
    return _client.call(() async {
      final response = await _client.dio.get('/marketplace/orders/vendor');
      return (response.data as List).cast<Map<String, dynamic>>().map(MarketplaceOrderItemApi.fromApi).toList();
    });
  }

  Future<MarketplaceOrderItemApi> respondToItem(String itemId, {required OrderItemStatus status}) {
    return _client.call(() async {
      final response = await _client.dio.patch('/marketplace/orders/items/$itemId/status', data: {'status': status.apiValue});
      return MarketplaceOrderItemApi.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<void> markItemRead(String itemId) {
    return _client.call(() async {
      await _client.dio.patch('/marketplace/orders/items/$itemId/read');
    });
  }
}
