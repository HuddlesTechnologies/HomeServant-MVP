import '../features/Market place/models/order_options.dart';
import 'api_client.dart';
import 'models/marketplace_api.dart';
import 'models/vendor.dart';

class MarketplaceProductsRepository {
  MarketplaceProductsRepository(this._client);

  final ApiClient _client;

  Future<List<MarketplaceProductApi>> findMany({MarketplaceCategory? category, String? search, String? vendorId}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/marketplace/products',
        queryParameters: {
          if (category != null) 'category': category.apiValue,
          if (search != null && search.isNotEmpty) 'search': search,
          if (vendorId != null) 'vendorId': vendorId,
          'pageSize': 100,
        },
      );
      final items = (response.data['items'] as List).cast<Map<String, dynamic>>();
      return items.map(MarketplaceProductApi.fromApi).toList();
    });
  }

  Future<MarketplaceProductApi> findOne(String id) {
    return _client.call(() async {
      final response = await _client.dio.get('/marketplace/products/$id');
      return MarketplaceProductApi.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<List<MarketplaceProductApi>> mine() {
    return _client.call(() async {
      final response = await _client.dio.get('/marketplace/products/mine');
      return (response.data as List).cast<Map<String, dynamic>>().map(MarketplaceProductApi.fromApi).toList();
    });
  }

  Future<MarketplaceProductApi> create({
    required String name,
    required String description,
    required int price,
    required int stock,
    required MarketplaceCategory category,
    required List<String> imageUrls,
    required Set<FulfillmentMethod> fulfillmentOptions,
    String? videoUrl,
  }) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/marketplace/products',
        data: {
          'name': name,
          'description': description,
          'price': price,
          'stock': stock,
          'category': category.apiValue,
          'imageUrls': imageUrls,
          'fulfillmentOptions': fulfillmentOptions.map((f) => f.apiValue).toList(),
          if (videoUrl != null) 'videoUrl': videoUrl,
        },
      );
      return MarketplaceProductApi.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<void> remove(String id) {
    return _client.call(() async {
      await _client.dio.delete('/marketplace/products/$id');
    });
  }
}
