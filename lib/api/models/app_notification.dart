enum NotificationType {
  referralSignup,
  vendorApproved,
  vendorRejected,
  vendorSuspended,
  vendorUnsuspended,
  bookingStatus,
  marketplaceOrderStatus,
  newMessage,
  reportAssigned,
  threadTransferred,
  rentExpiryReminder,
  newListingMessage,
  supportThreadResolved;

  static NotificationType fromApi(String value) => switch (value) {
    'REFERRAL_SIGNUP' => NotificationType.referralSignup,
    'VENDOR_APPROVED' => NotificationType.vendorApproved,
    'VENDOR_REJECTED' => NotificationType.vendorRejected,
    'VENDOR_SUSPENDED' => NotificationType.vendorSuspended,
    'VENDOR_UNSUSPENDED' => NotificationType.vendorUnsuspended,
    'BOOKING_STATUS' => NotificationType.bookingStatus,
    'MARKETPLACE_ORDER_STATUS' => NotificationType.marketplaceOrderStatus,
    'NEW_MESSAGE' => NotificationType.newMessage,
    'REPORT_ASSIGNED' => NotificationType.reportAssigned,
    'THREAD_TRANSFERRED' => NotificationType.threadTransferred,
    'RENT_EXPIRY_REMINDER' => NotificationType.rentExpiryReminder,
    'NEW_LISTING_MESSAGE' => NotificationType.newListingMessage,
    'SUPPORT_THREAD_RESOLVED' => NotificationType.supportThreadResolved,
    _ => NotificationType.referralSignup,
  };
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.threadId,
    this.silent = false,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  /// The chat thread a message/transfer/resolved notification is about —
  /// lets the detail screen show its current status and open it. Null for
  /// other types, and for notifications created before this was recorded.
  final String? threadId;

  /// Only ever set on a live socket push, never on GET /notifications: the
  /// server's way of saying "update the list, but no banner or sound" — a
  /// follow-up message folded into an existing alert, or an alert for an
  /// admin who's set themselves Away.
  final bool silent;

  bool get isRead => readAt != null;

  /// This notification, marked read now — keeps every other field
  /// (rebuilding it by hand used to drop [threadId], so a read chat
  /// notification could no longer open its conversation).
  AppNotification markedRead() => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    createdAt: createdAt,
    readAt: readAt ?? DateTime.now(),
    threadId: threadId,
    silent: silent,
  );

  factory AppNotification.fromApi(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    type: NotificationType.fromApi(json['type'] as String),
    title: json['title'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    readAt: json['readAt'] != null ? DateTime.parse(json['readAt'] as String) : null,
    threadId: json['threadId'] as String?,
    silent: json['silent'] as bool? ?? false,
  );
}
