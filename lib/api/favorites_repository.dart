import '../features/dashboard/models/property.dart';
import 'api_client.dart';

class FavoritesRepository {
  FavoritesRepository(this._client);

  final ApiClient _client;

  /// Returns the favorited properties directly (unwrapping the `Favorite`
  /// join rows) — nothing in the UI needs the join row's own id.
  Future<List<Property>> mine() {
    return _client.call(() async {
      final response = await _client.dio.get('/favorites');
      return (response.data as List)
          .cast<Map<String, dynamic>>()
          .map((json) => Property.fromApi(json['property'] as Map<String, dynamic>))
          .toList();
    });
  }

  Future<bool> toggle(String propertyId) {
    return _client.call(() async {
      final response = await _client.dio.post('/favorites/$propertyId/toggle');
      return response.data['favorited'] as bool;
    });
  }
}
