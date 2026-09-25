class ThreadParticipant {
  const ThreadParticipant({required this.id, this.fullName, this.profilePhotoUrl});

  final String id;
  final String? fullName;
  final String? profilePhotoUrl;

  factory ThreadParticipant.fromApi(Map<String, dynamic> json) => ThreadParticipant(
    id: json['id'] as String,
    fullName: json['fullName'] as String?,
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
  );
}

enum MessageType { text, propertyPreview }

MessageType _messageTypeFromApi(String? value) => value == 'propertyPreview' ? MessageType.propertyPreview : MessageType.text;

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.type = MessageType.text,
    this.previewPropertyTitle,
    this.previewPropertyImageUrl,
    this.previewPropertyPrice,
    this.previewPropertyPriceUnit,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Sending the first message in a thread that has a `propertyId`
  /// automatically gets `propertyPreview` server-side — the client never
  /// sets this itself, only renders whatever comes back.
  final MessageType type;
  final String? previewPropertyTitle;
  final String? previewPropertyImageUrl;
  final int? previewPropertyPrice;
  final String? previewPropertyPriceUnit;

  factory ChatMessage.fromApi(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    threadId: json['threadId'] as String,
    senderId: json['senderId'] as String,
    senderName: (json['sender'] as Map<String, dynamic>?)?['fullName'] as String? ?? 'User',
    body: json['body'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    readAt: (json['readAt'] as String?) != null ? DateTime.parse(json['readAt'] as String) : null,
    type: _messageTypeFromApi(json['type'] as String?),
    previewPropertyTitle: json['previewPropertyTitle'] as String?,
    previewPropertyImageUrl: json['previewPropertyImageUrl'] as String?,
    previewPropertyPrice: json['previewPropertyPrice'] as int?,
    previewPropertyPriceUnit: json['previewPropertyPriceUnit'] as String?,
  );
}

/// A conversation summary as returned by `GET /threads` — the other
/// participant(s), the property it's about (if any), and enough of the
/// last message to render a preview row without a second request.
class ChatThread {
  const ChatThread({
    required this.id,
    required this.otherParticipants,
    required this.unreadCount,
    required this.updatedAt,
    this.propertyId,
    this.propertyTitle,
    this.orderId,
    this.orderProductName,
    this.lastMessage,
  });

  final String id;
  final List<ThreadParticipant> otherParticipants;
  final String? propertyId;
  final String? propertyTitle;

  /// Set instead of propertyId for a marketplace pickup-coordination
  /// thread — see backend/README.md's Chat section.
  final String? orderId;
  final String? orderProductName;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;

  String get otherParticipantName =>
      otherParticipants.isEmpty ? 'User' : (otherParticipants.first.fullName ?? 'User');

  factory ChatThread.fromApi(Map<String, dynamic> json) {
    final property = json['property'] as Map<String, dynamic>?;
    final order = json['order'] as Map<String, dynamic>?;
    final lastMessage = json['lastMessage'] as Map<String, dynamic>?;
    return ChatThread(
      id: json['id'] as String,
      otherParticipants: (json['otherParticipants'] as List)
          .cast<Map<String, dynamic>>()
          .map(ThreadParticipant.fromApi)
          .toList(),
      propertyId: property?['id'] as String?,
      propertyTitle: property?['title'] as String?,
      orderId: order?['id'] as String?,
      orderProductName: order?['productName'] as String?,
      lastMessage: lastMessage != null ? ChatMessage.fromApi(lastMessage) : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
