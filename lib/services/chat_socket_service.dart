import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../api/api_config.dart';
import '../api/models/app_notification.dart';

class ChatSocketMessage {
  const ChatSocketMessage({required this.threadId, required this.message});

  final String threadId;
  final Map<String, dynamic> message;
}

/// Real-time chat delivery — before this, a thread's messages only ever
/// loaded once, when the screen opened; there was no polling and no push,
/// so a message sent by the other party while you were already looking at
/// the thread just never appeared until you left and reopened it.
///
/// One socket per signed-in session (connected in AppState right after
/// login/session-restore, disconnected on logout), independent of any
/// particular open [ChatThreadScreen] — [onNewMessage] is a broadcast
/// stream every open thread screen filters by its own thread id.
class ChatSocketService {
  io.Socket? _socket;
  final _controller = StreamController<ChatSocketMessage>.broadcast();
  final _notificationController = StreamController<AppNotification>.broadcast();
  final _readController = StreamController<String>.broadcast();

  Stream<ChatSocketMessage> get onNewMessage => _controller.stream;

  /// Fires with a thread id the instant the *other* participant marks that
  /// thread read (see backend ChatController.markRead) — lets an already-
  /// open ChatThreadScreen flip its own sent messages to "Seen" live
  /// instead of only finding out on the next full reload.
  Stream<String> get onRead => _readController.stream;

  /// Fires the instant a new `Notification` row is created for this user
  /// anywhere on the backend (chat, admin, payments, reports, …) — the
  /// global banner overlay is the one thing that listens to this; it
  /// carries the exact same shape `GET /notifications` already returns per
  /// row, so [AppNotification.fromApi] parses it unchanged.
  Stream<AppNotification> get onNotification => _notificationController.stream;

  void connect(String accessToken) {
    disconnect();
    // The Gateway has no namespace/prefix — it listens on the bare
    // origin's default socket.io path, not under the REST API's `/api`
    // prefix (that prefix is HTTP-routing-only, set via
    // `app.setGlobalPrefix` on the Nest side).
    final origin = apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final socket = io.io(
      origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': accessToken})
          .build(),
    );
    socket.onConnectError((_) {});
    socket.onError((_) {});
    socket.on('message:new', (data) {
      if (data is Map) {
        final threadId = data['threadId'] as String?;
        final message = data['message'];
        if (threadId != null && message is Map) {
          _controller.add(ChatSocketMessage(threadId: threadId, message: Map<String, dynamic>.from(message)));
        }
      }
    });
    socket.on('message:read', (data) {
      if (data is Map) {
        final threadId = data['threadId'] as String?;
        if (threadId != null) _readController.add(threadId);
      }
    });
    socket.on('notification:new', (data) {
      if (data is Map) {
        try {
          _notificationController.add(AppNotification.fromApi(Map<String, dynamic>.from(data)));
        } catch (_) {
          // Malformed/unexpected payload shape — drop it rather than crash
          // the socket event handler.
        }
      }
    });
    socket.connect();
    _socket = socket;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
