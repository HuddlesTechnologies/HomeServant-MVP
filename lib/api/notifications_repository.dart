import 'api_client.dart';
import 'models/app_notification.dart';

class NotificationsRepository {
  NotificationsRepository(this._client);

  final ApiClient _client;

  Future<List<AppNotification>> findMine() {
    return _client.call(() async {
      final response = await _client.dio.get('/notifications');
      return (response.data as List).cast<Map<String, dynamic>>().map(AppNotification.fromApi).toList();
    });
  }

  Future<int> unreadCount() {
    return _client.call(() async {
      final response = await _client.dio.get('/notifications/unread-count');
      return response.data['count'] as int;
    });
  }

  Future<void> markRead(String id) {
    return _client.call(() async {
      await _client.dio.patch('/notifications/$id/read');
    });
  }

  Future<void> markAllRead() {
    return _client.call(() async {
      await _client.dio.patch('/notifications/read-all');
    });
  }
}
