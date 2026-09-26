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
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromApi(Map<String, dynamic> json) => AppNotification(
    id: json['id'] as String,
    type: NotificationType.fromApi(json['type'] as String),
    title: json['title'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    readAt: json['readAt'] != null ? DateTime.parse(json['readAt'] as String) : null,
  );
}
