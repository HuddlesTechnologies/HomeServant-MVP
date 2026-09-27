import 'api_client.dart';

/// Web Push registration (backend PushController).
class PushRepository {
  PushRepository(this._client);

  final ApiClient _client;

  /// null when the server has no VAPID keys configured (push is off).
  Future<String?> publicKey() => _client.call(() async {
    final response = await _client.dio.get('/push/public-key');
    return (response.data as Map<String, dynamic>)['publicKey'] as String?;
  });

  Future<void> subscribe(Map<String, dynamic> subscription) => _client.call(() async {
    await _client.dio.post('/push/subscriptions', data: subscription);
  });

  Future<void> unsubscribe(String endpoint) => _client.call(() async {
    await _client.dio.delete('/push/subscriptions', data: {'endpoint': endpoint});
  });
}
