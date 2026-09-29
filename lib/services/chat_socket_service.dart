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
  final _claimedController = StreamController<String>.broadcast();
  final _badgesChangedController = StreamController<void>.broadcast();
  final _bannedController = StreamController<String?>.broadcast();
  final _accessRevokedController = StreamController<String>.broadcast();
  final _reconnectedController = StreamController<void>.broadcast();
  final _threadsChangedController = StreamController<void>.broadcast();
  final _listingsChangedController = StreamController<void>.broadcast();
  Timer? _retryTimer;
  int _retryAttempt = 0;

  Stream<ChatSocketMessage> get onNewMessage => _controller.stream;

  /// Fires when the socket comes back after being disconnected. Anything
  /// pushed while it was down was missed, so listeners refetch (the inbox,
  /// an open thread, notifications).
  Stream<void> get onReconnected => _reconnectedController.stream;

  /// Fires whenever a conversation list may be out of date: a message
  /// arrived, the socket reconnected, or this device started a chat or
  /// sent a message ([notifyThreadsChanged]). The socket only pushes the
  /// *other* side's messages, so a chat you just started (e.g. with
  /// support) never reached your own inbox until a reload.
  Stream<void> get onThreadsChanged => _threadsChangedController.stream;

  void notifyThreadsChanged() => _threadsChangedController.add(null);

  /// Fires when browse results may have changed for everyone — a listing
  /// was edited, or a rental was paid for, moved into or relisted (backend
  /// ChatGateway's `listings:changed`, sent to every connected app).
  Stream<void> get onListingsChanged => _listingsChangedController.stream;

  /// Fires with a thread id the instant the *other* participant marks that
  /// thread read (see backend ChatController.markRead) — lets an already-
  /// open ChatThreadScreen flip its own sent messages to "Seen" live
  /// instead of only finding out on the next full reload.
  Stream<String> get onRead => _readController.stream;

  /// Fires with a thread id the instant any admin claims a support thread
  /// (opening it from the Support Queue, or being the first to reply — see
  /// backend ChatService.claimThread/attemptClaim) — lets every other
  /// admin's open Support Queue tab drop that row live instead of only on
  /// their next new message.
  Stream<String> get onThreadClaimed => _claimedController.stream;

  /// Fires the instant a new `Notification` row is created for this user
  /// anywhere on the backend (chat, admin, payments, reports, …) — the
  /// global banner overlay is the one thing that listens to this; it
  /// carries the exact same shape `GET /notifications` already returns per
  /// row, so [AppNotification.fromApi] parses it unchanged.
  Stream<AppNotification> get onNotification => _notificationController.stream;

  /// Fires whenever a mutation on the backend changes one of the admin
  /// console's nav badge counts (a report submitted/resolved/transferred,
  /// a vendor application submitted/approved/rejected, an admin invite
  /// sent/confirmed) — AdminShell listens to this and refetches all of
  /// them, live, instead of only ever loading them once at console
  /// startup. No payload: cheaper to just refetch the handful of COUNT
  /// queries than to keep track of which specific badge changed.
  Stream<void> get onAdminBadgesChanged => _badgesChangedController.stream;

  /// This account was just permanently banned (the ban reason, if given) —
  /// AppState signs out and explains.
  Stream<String?> get onAccountBanned => _bannedController.stream;

  /// Fires with a thread id when the server removes this socket from that
  /// thread's live room because the user lost access to it (another admin
  /// took over a support conversation — see backend
  /// ChatGateway.evictUnauthorizedFromThread).
  Stream<String> get onAccessRevoked => _accessRevokedController.stream;

  /// [tokenProvider] is asked for a token on *every* connect and reconnect
  /// (see ApiClient.freshAccessToken), not just the first.
  void connect(Future<String?> Function() tokenProvider) {
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
          .enableReconnection()
          .build(),
    );
    socket.auth = (void Function(Map<String, dynamic>) send) {
      tokenProvider().then((token) => send({'token': token ?? ''})).catchError((_) => send({'token': ''}));
    };
    var connectedBefore = false;
    socket.onConnect((_) {
      _retryAttempt = 0;
      if (connectedBefore) {
        _reconnectedController.add(null);
        _threadsChangedController.add(null);
      }
      connectedBefore = true;
    });
    // The server rejects a bad/expired token by disconnecting the socket
    // itself ("io server disconnect"), and socket.io never auto-reconnects
    // after that — retry ourselves with backoff; the auth callback above
    // fetches a fresh token each time.
    socket.onDisconnect((reason) {
      if (reason == 'io server disconnect' && identical(_socket, socket)) _scheduleRetry(socket);
    });
    socket.onConnectError((_) {});
    socket.onError((_) {});
    socket.on('message:new', (data) {
      if (data is Map) {
        final threadId = data['threadId'] as String?;
        final message = data['message'];
        if (threadId != null && message is Map) {
          _controller.add(ChatSocketMessage(threadId: threadId, message: Map<String, dynamic>.from(message)));
          _threadsChangedController.add(null);
        }
      }
    });
    socket.on('message:read', (data) {
      if (data is Map) {
        final threadId = data['threadId'] as String?;
        if (threadId != null) _readController.add(threadId);
      }
    });
    socket.on('thread:claimed', (data) {
      if (data is Map) {
        final threadId = data['threadId'] as String?;
        if (threadId != null) _claimedController.add(threadId);
      }
    });
    socket.on('admin:badges-changed', (_) => _badgesChangedController.add(null));
    socket.on('listings:changed', (_) => _listingsChangedController.add(null));
    socket.on('account:banned', (data) => _bannedController.add(data is Map ? data['reason'] as String? : null));
    socket.on('thread:access-revoked', (data) {
      if (data is Map) {
        final threadId = data['threadId'] as String?;
        if (threadId != null) _accessRevokedController.add(threadId);
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

  void _scheduleRetry(io.Socket socket) {
    _retryTimer?.cancel();
    final seconds = [2, 5, 10, 30, 60][_retryAttempt.clamp(0, 4)];
    _retryAttempt++;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (identical(_socket, socket) && !socket.connected) socket.connect();
    });
  }

  void disconnect() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _socket?.dispose();
    _socket = null;
  }
}
