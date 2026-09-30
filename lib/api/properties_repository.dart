import '../features/dashboard/models/property.dart';
import 'api_client.dart';

class PropertiesRepository {
  PropertiesRepository(this._client);

  final ApiClient _client;

  /// Fetches every matching property, following `total` across as many
  /// 100-item pages as it takes, so a list with more than 100 listings is
  /// never cut short.
  Future<List<Property>> findMany({String? state, String? category, String? landlordId}) {
    return _client.call(() async {
      const pageSize = 100;
      final all = <Property>[];
      var page = 1;
      while (true) {
        final response = await _client.dio.get(
          '/properties',
          queryParameters: {
            if (state != null) 'state': state,
            if (category != null) 'category': Property.categoryApiValue(category),
            if (landlordId != null) 'landlordId': landlordId,
            'page': page,
            'pageSize': pageSize,
          },
        );
        final data = response.data as Map<String, dynamic>;
        final items = (data['items'] as List).cast<Map<String, dynamic>>();
        all.addAll(items.map(Property.fromApi));
        final total = data['total'] as int? ?? all.length;
        if (items.isEmpty || all.length >= total) break;
        page++;
      }
      return all;
    });
  }

  Future<Property> findOne(String id) {
    return _client.call(() async {
      final response = await _client.dio.get('/properties/$id');
      return Property.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<Property> create(Property property) {
    return _client.call(() async {
      final response = await _client.dio.post('/properties', data: property.toCreateJson());
      return Property.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Partial update (e.g. the messaging toggle, or a full re-edit of the
  /// listing) — `PATCH /properties/:id`.
  Future<Property> update(String id, Map<String, dynamic> data) {
    return _client.call(() async {
      final response = await _client.dio.patch('/properties/$id', data: data);
      return Property.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// What a paid "Featured" ad on [id] costs and how long it runs.
  Future<({int feeNaira, int days, DateTime? featuredUntil, DateTime wouldRunUntil})> promotionQuote(String id) {
    return _client.call(() async {
      final response = await _client.dio.get('/properties/$id/promotions/quote');
      final data = response.data as Map<String, dynamic>;
      return (
        feeNaira: data['feeNaira'] as int,
        days: data['days'] as int,
        featuredUntil: data['featuredUntil'] != null ? DateTime.parse(data['featuredUntil'] as String) : null,
        wouldRunUntil: DateTime.parse(data['wouldRunUntil'] as String),
      );
    });
  }

  /// Starts Paystack checkout for a featured ad; returns the page to pay on.
  Future<String> startPromotion(String id) {
    return _client.call(() async {
      final response = await _client.dio.post('/properties/$id/promotions');
      return response.data['authorizationUrl'] as String;
    });
  }

  Future<void> remove(String id) {
    return _client.call(() async {
      await _client.dio.delete('/properties/$id');
    });
  }
}
