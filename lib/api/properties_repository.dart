import '../features/dashboard/models/property.dart';
import 'api_client.dart';

class PropertiesRepository {
  PropertiesRepository(this._client);

  final ApiClient _client;

  Future<List<Property>> findMany({String? state, String? category, String? landlordId}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/properties',
        queryParameters: {
          if (state != null) 'state': state,
          if (category != null) 'category': Property.categoryApiValue(category),
          if (landlordId != null) 'landlordId': landlordId,
          'pageSize': 100,
        },
      );
      final items = (response.data['items'] as List).cast<Map<String, dynamic>>();
      return items.map(Property.fromApi).toList();
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

  Future<void> remove(String id) {
    return _client.call(() async {
      await _client.dio.delete('/properties/$id');
    });
  }
}
