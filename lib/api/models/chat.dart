class ThreadParticipant {
  const ThreadParticipant({
    required this.id,
    this.fullName,
    this.profilePhotoUrl,
    this.isOnline = false,
    this.lastActiveAt,
  });

  final String id;
  final String? fullName;
  final String? profilePhotoUrl;

  /// A live snapshot at the moment `GET /threads` was called (see backend
  /// ChatService.findForUser/PresenceService) — not a subscription, so it
  /// only updates on the next refetch.
  final bool isOnline;
  final DateTime? lastActiveAt;

  factory ThreadParticipant.fromApi(Map<String, dynamic> json) => ThreadParticipant(
    id: json['id'] as String,
    fullName: json['fullName'] as String?,
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
    isOnline: json['isOnline'] as bool? ?? false,
    lastActiveAt: json['lastActiveAt'] != null ? DateTime.parse(json['lastActiveAt'] as String) : null,
  );
}

/// [system]: an automatic notice with no sender (e.g. "refund initiated,
/// further messaging is no longer available") — see backend
/// ChatService.postBookingSystemMessage.
enum MessageType { text, propertyPreview, image, system }

// The backend returns Prisma's raw MessageType enum member (TEXT /
// PROPERTY_PREVIEW / IMAGE) verbatim in JSON — nothing camelCases it — so
// this has to match that exact casing. This previously compared against
// 'propertyPreview'/lowerCamelCase, which never matched anything the API
// actually sends: property-preview messages silently never rendered as
// their special card, always falling back to a plain text bubble instead.
MessageType _messageTypeFromApi(String? value) => switch (value) {
  'PROPERTY_PREVIEW' => MessageType.propertyPreview,
  'IMAGE' => MessageType.image,
  'SYSTEM' => MessageType.system,
  _ => MessageType.text,
};

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
    this.attachmentUrl,
    this.previewPropertyTitle,
    this.previewPropertyImageUrl,
    this.previewPropertyPrice,
    this.previewPropertyPriceUnit,
  });

  final String id;
  final String threadId;
  /// Null once the sender's account has been deleted — Message.sender is
  /// `onDelete: SetNull`, so their messages stay in the thread without one.
  /// Parsing this as non-null used to throw on any thread holding such a
  /// message, failing the whole inbox load ("Couldn't load messages").
  final String? senderId;
  final String senderName;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Sending the first message in a thread that has a `propertyId`
  /// automatically gets `propertyPreview` server-side — the client never
  /// sets this itself, only renders whatever comes back.
  final MessageType type;

  /// Set only when [type] is [MessageType.image] — see backend
  /// Message.attachmentUrl.
  final String? attachmentUrl;
  final String? previewPropertyTitle;
  final String? previewPropertyImageUrl;
  final int? previewPropertyPrice;
  final String? previewPropertyPriceUnit;

  factory ChatMessage.fromApi(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    threadId: json['threadId'] as String,
    senderId: json['senderId'] as String?,
    senderName:
        (json['sender'] as Map<String, dynamic>?)?['fullName'] as String? ??
        (json['senderId'] == null ? 'Deleted user' : 'User'),
    body: json['body'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    readAt: (json['readAt'] as String?) != null ? DateTime.parse(json['readAt'] as String) : null,
    type: _messageTypeFromApi(json['type'] as String?),
    attachmentUrl: json['attachmentUrl'] as String?,
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
    this.isSupport = false,
    this.resolved = false,
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

  /// A "Contact Support" thread (see ChatRepository.openSupportThread) —
  /// unclaimed until an admin replies, so [otherParticipants] may be empty.
  final bool isSupport;

  /// Once true, this thread is hidden from a non-admin caller's own
  /// `GET /threads` response entirely (see the backend's findForUser) —
  /// this field only ever reads `true` on the admin side, which still gets
  /// it back until the 30-day cleanup cron removes it.
  final bool resolved;

  String get otherParticipantName {
    if (otherParticipants.isEmpty) return isSupport ? 'HomeServant Support' : 'User';
    return otherParticipants.first.fullName ?? 'User';
  }

  /// "Active now" / "Last active 3h ago" for the other participant, or
  /// null when there isn't one yet (an unclaimed support thread) — the
  /// caller decides how/whether to render it (see ChatThreadListTile,
  /// ChatThreadScreen's app bar subtitle).
  ThreadParticipant? get otherParticipant => otherParticipants.isEmpty ? null : otherParticipants.first;

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
      isSupport: json['isSupport'] as bool? ?? false,
      resolved: json['resolved'] as bool? ?? false,
    );
  }
}

/// One row in the admin console's shared Support Queue
/// (`GET /threads/support-queue`) — distinct from [ChatThread] since an
/// unclaimed queue entry has no admin participant yet to derive a name
/// from; the requester is returned directly instead.
class SupportQueueThread {
  const SupportQueueThread({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.assignedAdminId,
    this.requesterId,
    this.requesterName,
    this.lastMessage,
  });

  final String id;

  /// Always null in practice — the backend only ever returns unclaimed
  /// threads from this endpoint now (see ChatService.findSupportQueue);
  /// kept here as a faithful mirror of the API response shape rather than
  /// dropped outright.
  final String? assignedAdminId;

  /// Needed to pass as `ChatThreadScreen.adminViewOfUserId` when opening a
  /// ticket straight from the queue — without it, the collapsible user-info
  /// panel had no id to fetch a profile for and never appeared for a
  /// support conversation opened this way.
  final String? requesterId;
  final String? requesterName;
  final ChatMessage? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory SupportQueueThread.fromApi(Map<String, dynamic> json) {
    final requester = json['requester'] as Map<String, dynamic>?;
    final lastMessage = json['lastMessage'] as Map<String, dynamic>?;
    return SupportQueueThread(
      id: json['id'] as String,
      assignedAdminId: json['assignedAdminId'] as String?,
      requesterId: requester?['id'] as String?,
      requesterName: requester?['fullName'] as String?,
      lastMessage: lastMessage != null ? ChatMessage.fromApi(lastMessage) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

/// A person reference inside a [ThreadSummary] (an admin, or the other
/// side of the conversation).
class ThreadPersonRef {
  const ThreadPersonRef({required this.id, this.fullName, this.profilePhotoUrl});

  final String id;
  final String? fullName;
  final String? profilePhotoUrl;

  String get displayName => fullName?.trim().isNotEmpty == true ? fullName! : 'an admin';

  static ThreadPersonRef? fromApi(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return ThreadPersonRef(
      id: json['id'] as String,
      fullName: json['fullName'] as String?,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
    );
  }
}

/// Where a thread stands now, for the signed-in user — `GET
/// /threads/:id/summary` (see backend ChatService.getThreadSummary). Shown
/// when a chat notification is opened.
class ThreadSummary {
  const ThreadSummary({
    required this.id,
    required this.isSupport,
    required this.resolved,
    required this.canView,
    required this.canReply,
    required this.otherParticipants,
    this.canReassign = false,
    this.lockedReason,
    this.resolvedAt,
    this.assignedAdmin,
    this.lastTransferFrom,
    this.lastTransferTo,
  });

  final String id;
  final bool isSupport;
  final bool resolved;
  final DateTime? resolvedAt;
  final ThreadPersonRef? assignedAdmin;
  final ThreadPersonRef? lastTransferFrom;
  final ThreadPersonRef? lastTransferTo;
  final List<ThreadPersonRef> otherParticipants;
  final bool canView;
  final bool canReply;

  /// Super admins only: can hand this open support conversation to another
  /// admin even though they aren't handling it themselves.
  final bool canReassign;

  /// Tenant/landlord threads only: why neither side can message right now
  /// (not paid yet, or the booking was refunded) — see backend
  /// ChatService.landlordTenantBlockReason. Null when messaging is open.
  final String? lockedReason;

  factory ThreadSummary.fromApi(Map<String, dynamic> json) {
    final transfer = json['lastTransfer'] as Map<String, dynamic>?;
    return ThreadSummary(
      id: json['id'] as String,
      isSupport: json['isSupport'] as bool? ?? false,
      resolved: json['resolved'] as bool? ?? false,
      resolvedAt: json['resolvedAt'] != null ? DateTime.parse(json['resolvedAt'] as String) : null,
      assignedAdmin: ThreadPersonRef.fromApi(json['assignedAdmin']),
      lastTransferFrom: ThreadPersonRef.fromApi(transfer?['fromAdmin']),
      lastTransferTo: ThreadPersonRef.fromApi(transfer?['toAdmin']),
      otherParticipants: (json['otherParticipants'] as List? ?? const [])
          .map(ThreadPersonRef.fromApi)
          .whereType<ThreadPersonRef>()
          .toList(),
      canView: json['canView'] as bool? ?? false,
      canReply: json['canReply'] as bool? ?? false,
      canReassign: json['canReassign'] as bool? ?? false,
      lockedReason: json['lockedReason'] as String?,
    );
  }
}
