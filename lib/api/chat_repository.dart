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

  /// Finds-or-creates the caller's own "Contact Support" thread — see
  /// backend ChatService.openSupportThread. Unlike [openThread], there's no
  /// recipient to pick; any admin can pick it up from the shared queue.
  Future<ChatThread> openSupportThread() {
    return _client.call(() async {
      final response = await _client.dio.post('/threads/support');
      final threadId = response.data['id'] as String;
      final threads = await myThreads();
      return threads.firstWhere((t) => t.id == threadId);
    });
  }

  /// Admin-only — every open "Contact Support" thread, claimed or not.
  Future<List<SupportQueueThread>> supportQueue() {
    return _client.call(() async {
      final response = await _client.dio.get('/threads/support-queue');
      return (response.data as List).cast<Map<String, dynamic>>().map(SupportQueueThread.fromApi).toList();
    });
  }

  /// Admin-only — marks a support thread resolved, which hides it from the
  /// user's own inbox from then on (see backend ChatService.findForUser).
  Future<void> resolveThread(String threadId) {
    return _client.call(() async {
      await _client.dio.patch('/threads/$threadId/resolve');
    });
  }

  /// Admin-only — explicitly claims an unattended support thread, called
  /// right before navigating into it from the Support Queue so it moves
  /// into the claiming admin's own inbox immediately, not just once they
  /// reply. Throws (via `_client.call`'s ApiException wrapping) if another
  /// admin claimed it a moment earlier — see backend ChatService.claimThread.
  Future<void> claimThread(String threadId) {
    return _client.call(() async {
      await _client.dio.patch('/threads/$threadId/claim');
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

  Future<ChatMessage> send(String threadId, String body, {String? attachmentUrl}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/threads/$threadId/messages',
        data: {if (body.isNotEmpty) 'body': body, if (attachmentUrl != null) 'attachmentUrl': attachmentUrl},
      );
      return ChatMessage.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<void> markRead(String threadId) {
    return _client.call(() async {
      await _client.dio.patch('/threads/$threadId/read');
    });
  }

  /// Admin-only — hands the thread off to another admin. The backend
  /// (`chat.service.ts`'s `transferThread`) already sends the new admin an
  /// in-app notification + email; this just adds the missing client call.
  Future<void> transferThread(String threadId, String adminId) {
    return _client.call(() async {
      await _client.dio.patch('/threads/$threadId/transfer', data: {'adminId': adminId});
    });
  }
}
