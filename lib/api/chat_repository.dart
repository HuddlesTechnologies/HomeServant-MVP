import 'api_client.dart';
import 'models/chat.dart';
import 'models/support_tools.dart';

/// Wraps `/threads`. Live updates come from ChatSocketService; inbox
/// screens refetch on its onThreadsChanged stream.
class ChatRepository {
  ChatRepository(this._client);

  final ApiClient _client;

  /// Set by AppState: called after this device starts a conversation or
  /// sends a message, so open inbox screens refresh (the socket only
  /// pushes the other side's messages) — see ChatSocketService.onThreadsChanged.
  void Function()? onLocalChange;

  /// Set by AppState: called after a conversation is marked read, so the
  /// notifications about it are cleared locally too.
  void Function(String threadId)? onThreadRead;

  Future<List<ChatThread>> myThreads() {
    return _client.call(() async {
      final response = await _client.dio.get('/threads');
      return (response.data as List).cast<Map<String, dynamic>>().map(ChatThread.fromApi).toList();
    });
  }

  /// Finds-or-creates the caller's own "Contact Support" thread — see
  /// backend ChatService.openSupportThread. Unlike [openThread], there's no
  /// recipient to pick; any admin can pick it up from the shared queue.
  Future<ChatThread> openSupportThread({SupportTopic? topic}) {
    return _client.call(() async {
      final response = await _client.dio.post('/threads/support', data: {if (topic != null) 'topic': topic.apiValue});
      final threadId = response.data['id'] as String;
      final threads = await myThreads();
      onLocalChange?.call();
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
      onLocalChange?.call();
      return threads.firstWhere((t) => t.id == threadId);
    });
  }

  /// The customer ends their own support conversation (backend
  /// ChatService.endSupportThreadByCustomer).
  Future<void> endSupportThread(String threadId) {
    return _client.call(() async {
      await _client.dio.patch('/threads/$threadId/end');
      onLocalChange?.call();
    });
  }

  /// The customer's 1–5 rating of a resolved support conversation.
  Future<void> rateSupportThread(String threadId, int rating, {String? comment}) {
    return _client.call(() async {
      await _client.dio.post(
        '/threads/$threadId/rating',
        data: {'rating': rating, if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim()},
      );
    });
  }

  /// The thread's current status for this user — see [ThreadSummary].
  Future<ThreadSummary> summary(String threadId) {
    return _client.call(() async {
      final response = await _client.dio.get('/threads/$threadId/summary');
      return ThreadSummary.fromApi(response.data as Map<String, dynamic>);
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
      onLocalChange?.call();
      return ChatMessage.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<void> markRead(String threadId) {
    return _client.call(() async {
      await _client.dio.patch('/threads/$threadId/read');
      onThreadRead?.call(threadId);
    });
  }

  /// Support threads: who took it up and every hand-off since — for the
  /// handling admin and super admins (backend ChatService.getHandlingHistory).
  Future<ThreadHandlingHistory> handlingHistory(String threadId) {
    return _client.call(() async {
      final response = await _client.dio.get('/threads/$threadId/handling-history');
      return ThreadHandlingHistory.fromApi(response.data as Map<String, dynamic>);
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

  /// Super-admin only — hands an open support conversation to [adminId],
  /// whoever is handling it now (see backend ChatService.reassignThread).
  Future<void> reassignThread(String threadId, String adminId) {
    return _client.call(() async {
      await _client.dio.patch('/threads/$threadId/reassign', data: {'adminId': adminId});
    });
  }
}
