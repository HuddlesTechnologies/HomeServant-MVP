/// A support thread's lifecycle stage in the super-admin Chat Log —
/// [unattended] (red, nobody's claimed it yet — though in practice a chat
/// log entry is almost never seen in this state, since it's only ever
/// queried for the last 30 days and most tickets get claimed quickly),
/// [opened] (blue, claimed and still open) or [resolved] (green). Mirrors
/// the `status` string the backend's `GET /admin/chat-log` sends (see
/// ChatService.findChatLog).
enum ChatLogStatus {
  unattended,
  opened,
  resolved;

  static ChatLogStatus fromApi(String value) => switch (value) {
    'RESOLVED' => ChatLogStatus.resolved,
    'OPENED' => ChatLogStatus.opened,
    _ => ChatLogStatus.unattended,
  };

  String get label => switch (this) {
    ChatLogStatus.unattended => 'Unattended',
    ChatLogStatus.opened => 'Read',
    ChatLogStatus.resolved => 'Resolved',
  };
}

/// One row in the super-admin-only Chat Log (`GET /admin/chat-log`) —
/// every support thread from the last 30 days, regardless of who (if
/// anyone) is on it or whether it's resolved. Unlike [SupportQueueThread]/
/// [ChatThread], this carries the full transfer history
/// ([transferChain]), not just the current handler, since that's the
/// whole point of this screen.
class ChatLogEntry {
  const ChatLogEntry({
    required this.id,
    required this.status,
    this.requesterName,
    this.currentAdminName,
    this.transferChain = const [],
    this.lastMessageBody,
    required this.createdAt,
    this.resolvedAt,
  });

  final String id;
  final ChatLogStatus status;
  final String? requesterName;

  /// The admin currently on this thread (`Thread.assignedAdminId`) — null
  /// only for the rare case a chat-log entry is still genuinely unattended.
  final String? currentAdminName;

  /// Every admin this thread has ever been transferred between, in order
  /// (first handler first) — empty if it's never been transferred.
  final List<String> transferChain;
  final String? lastMessageBody;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  bool get wasTransferred => transferChain.length > 1;

  factory ChatLogEntry.fromApi(Map<String, dynamic> json) {
    final requester = json['requester'] as Map<String, dynamic>?;
    final currentAdmin = json['currentAdmin'] as Map<String, dynamic>?;
    final lastMessage = json['lastMessage'] as Map<String, dynamic>?;
    return ChatLogEntry(
      id: json['id'] as String,
      status: ChatLogStatus.fromApi(json['status'] as String),
      requesterName: requester?['fullName'] as String?,
      currentAdminName: currentAdmin?['fullName'] as String?,
      transferChain: (json['transferChain'] as List? ?? const []).cast<String>(),
      lastMessageBody: lastMessage?['body'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      resolvedAt: json['resolvedAt'] != null ? DateTime.parse(json['resolvedAt'] as String) : null,
    );
  }
}
