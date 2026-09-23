enum NotificationType {
  referralSignup;

  static NotificationType fromApi(String value) => switch (value) {
    'REFERRAL_SIGNUP' => NotificationType.referralSignup,
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
