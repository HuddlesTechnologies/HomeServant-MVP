import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../api/api_config.dart';

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

  Stream<ChatSocketMessage> get onNewMessage => _controller.stream;

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
    socket.connect();
    _socket = socket;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
