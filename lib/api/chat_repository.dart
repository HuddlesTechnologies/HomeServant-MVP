import 'api_client.dart';
import 'models/chat.dart';

/// Wraps `/threads`. There's no push/live layer yet (see
/// backend/README.md's Chat section) — screens using this poll by
/// refetching on focus/after sending rather than holding a subscription.
class ChatRepository {
  ChatRepository(this._client);

  final ApiClient _client;

  Future<List<ChatThread>> myThreads() {
    return _client.call(() async {
      final response = await _client.dio.get('/threads');
      return (response.data as List).cast<Map<String, dynamic>>().map(ChatThread.fromApi).toList();
    });
  }

  Future<ChatThread> openThread({required String recipientId, String? propertyId, String? orderId}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/threads',
        data: {
          'recipientId': recipientId,
          if (propertyId != null) 'propertyId': propertyId,
          if (orderId != null) 'orderId': orderId,
        },
      );
      // The create/find endpoint returns the raw Thread row (participants
      // as ThreadParticipant join rows, not yet shaped like a list-item
      // summary) — refetch the list-shaped version so callers always get
      // the same ChatThread shape regardless of which endpoint opened it.
      final threadId = response.data['id'] as String;
      final threads = await myThreads();
      return threads.firstWhere((t) => t.id == threadId);
    });
  }

  Future<List<ChatMessage>> messages(String threadId, {DateTime? before}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/threads/$threadId/messages',
        queryParameters: before != null ? {'before': before.toIso8601String()} : null,
      );
      return (response.data as List).cast<Map<String, dynamic>>().map(ChatMessage.fromApi).toList();
    });
  }

  Future<ChatMessage> send(String threadId, String body) {
    return _client.call(() async {
      final response = await _client.dio.post('/threads/$threadId/messages', data: {'body': body});
      return ChatMessage.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<void> markRead(String threadId) {
    return _client.call(() async {
      await _client.dio.patch('/threads/$threadId/read');
    });
  }
}
