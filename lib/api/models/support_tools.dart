import 'admin_models.dart' show AdminLevel;

/// What a support conversation is about (backend SupportTopic).
enum SupportTopic {
  payments('PAYMENTS', 'Payments'),
  booking('BOOKING', 'Booking'),
  account('ACCOUNT', 'Account'),
  listing('LISTING', 'Listing'),
  marketplace('MARKETPLACE', 'Marketplace'),
  other('OTHER', 'Other');

  const SupportTopic(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static SupportTopic? fromApi(Object? value) {
    for (final topic in values) {
      if (topic.apiValue == value) return topic;
    }
    return null;
  }
}

/// How urgent a support conversation is (backend SupportPriority).
enum SupportPriority {
  low('LOW', 'Low'),
  normal('NORMAL', 'Normal'),
  high('HIGH', 'High'),
  urgent('URGENT', 'Urgent');

  const SupportPriority(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static SupportPriority fromApi(Object? value) {
    for (final priority in values) {
      if (priority.apiValue == value) return priority;
    }
    return SupportPriority.normal;
  }
}

/// An admin-only note on a support conversation.
class SupportNote {
  const SupportNote({required this.id, required this.body, required this.createdAt, this.authorId, this.authorName});

  final String id;
  final String body;
  final DateTime createdAt;
  final String? authorId;
  final String? authorName;

  factory SupportNote.fromApi(Map<String, dynamic> json) {
    final author = json['author'] as Map<String, dynamic>?;
    final name = author?['fullName'] as String?;
    return SupportNote(
      id: json['id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      authorId: author?['id'] as String?,
      authorName: name?.trim().isNotEmpty == true ? name : author?['email'] as String?,
    );
  }
}

/// A shared ready-made answer admins can insert into a reply.
class SavedReply {
  const SavedReply({required this.id, required this.title, required this.body, this.createdById});

  final String id;
  final String title;
  final String body;
  final String? createdById;

  factory SavedReply.fromApi(Map<String, dynamic> json) => SavedReply(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    createdById: json['createdById'] as String?,
  );
}

/// An admin a conversation can be handed to, with what helps choose well.
class TransferTarget {
  const TransferTarget({
    required this.id,
    required this.email,
    required this.level,
    required this.onDuty,
    required this.isOnline,
    required this.openChats,
    this.fullName,
  });

  final String id;
  final String email;
  final String? fullName;
  final AdminLevel level;
  final bool onDuty;
  final bool isOnline;
  final int openChats;

  String get displayName => fullName?.trim().isNotEmpty == true ? fullName! : email;

  factory TransferTarget.fromApi(Map<String, dynamic> json) => TransferTarget(
    id: json['id'] as String,
    email: json['email'] as String,
    fullName: json['fullName'] as String?,
    level: AdminLevel.fromApi(json['adminLevel'] as String),
    onDuty: json['adminOnDuty'] as bool? ?? true,
    isOnline: json['isOnline'] as bool? ?? false,
    openChats: json['openChats'] as int? ?? 0,
  );
}

class ContextBooking {
  const ContextBooking({required this.propertyTitle, required this.status, required this.createdAt, this.tenantName});

  final String propertyTitle;
  final String status;
  final DateTime createdAt;
  final String? tenantName;

  factory ContextBooking.fromApi(Map<String, dynamic> json) => ContextBooking(
    propertyTitle: json['propertyTitle'] as String? ?? 'Property',
    status: json['status'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    tenantName: json['tenantName'] as String?,
  );
}

class ContextPayment {
  const ContextPayment({required this.amountKobo, required this.status, required this.purpose, required this.createdAt, required this.paid});

  final int amountKobo;
  final String status;
  final String purpose;
  final DateTime createdAt;

  /// true: the customer paid it; false: they received it.
  final bool paid;

  factory ContextPayment.fromApi(Map<String, dynamic> json) => ContextPayment(
    amountKobo: json['amount'] as int,
    status: json['status'] as String,
    purpose: json['purpose'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    paid: json['direction'] == 'PAID',
  );
}

class ContextPastChat {
  const ContextPastChat({required this.id, required this.resolved, required this.createdAt, this.topic});

  final String id;
  final bool resolved;
  final DateTime createdAt;
  final SupportTopic? topic;

  factory ContextPastChat.fromApi(Map<String, dynamic> json) => ContextPastChat(
    id: json['id'] as String,
    resolved: json['status'] == 'RESOLVED',
    createdAt: DateTime.parse(json['createdAt'] as String),
    topic: SupportTopic.fromApi(json['supportTopic']),
  );
}

/// `GET /threads/:id/customer-context` — the customer beside the chat.
class CustomerContext {
  const CustomerContext({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.joinedAt,
    required this.tenantBookings,
    required this.landlordBookings,
    required this.listingsTotal,
    required this.listingsOccupied,
    required this.payments,
    required this.reportsFiled,
    required this.openReportsOnListings,
    required this.pastChats,
    this.phone,
    this.deactivated = false,
    this.emailVerified = false,
    this.shopName,
  });

  final String userId;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final DateTime joinedAt;
  final bool deactivated;
  final bool emailVerified;
  final String? shopName;
  final List<ContextBooking> tenantBookings;
  final List<ContextBooking> landlordBookings;
  final int listingsTotal;
  final int listingsOccupied;
  final List<ContextPayment> payments;
  final int reportsFiled;
  final int openReportsOnListings;
  final List<ContextPastChat> pastChats;

  factory CustomerContext.fromApi(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    final listings = json['listings'] as Map<String, dynamic>? ?? const {};
    final reports = json['reports'] as Map<String, dynamic>? ?? const {};
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) =>
        (json[key] as List? ?? const []).cast<Map<String, dynamic>>().map(parse).toList();
    final fullName = user['fullName'] as String?;
    return CustomerContext(
      userId: user['id'] as String,
      name: fullName?.trim().isNotEmpty == true ? fullName! : user['email'] as String,
      email: user['email'] as String,
      phone: user['phoneNumber'] as String?,
      role: user['role'] as String,
      joinedAt: DateTime.parse(user['createdAt'] as String),
      deactivated: user['deactivatedAt'] != null,
      emailVerified: user['emailVerifiedAt'] != null,
      shopName: (user['vendorProfile'] as Map<String, dynamic>?)?['businessName'] as String?,
      tenantBookings: list('tenantBookings', ContextBooking.fromApi),
      landlordBookings: list('landlordBookings', ContextBooking.fromApi),
      listingsTotal: listings['total'] as int? ?? 0,
      listingsOccupied: listings['occupied'] as int? ?? 0,
      payments: list('payments', ContextPayment.fromApi),
      reportsFiled: reports['filed'] as int? ?? 0,
      openReportsOnListings: reports['openOnTheirListings'] as int? ?? 0,
      pastChats: list('pastChats', ContextPastChat.fromApi),
    );
  }
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

class SupportTotals {
  const SupportTotals(this.json);
  final Map<String, dynamic> json;

  int get conversations => json['conversations'] as int? ?? 0;
  int get resolved => json['resolved'] as int? ?? 0;
  double? get medianFirstResponseMinutes => _num(json['medianFirstResponseMinutes']);
  double? get p90FirstResponseMinutes => _num(json['p90FirstResponseMinutes']);
  double? get medianResolutionMinutes => _num(json['medianResolutionMinutes']);
  double? get averageRating => _num(json['averageRating']);
  int get ratings => json['ratings'] as int? ?? 0;
  int get transferred => json['transferred'] as int? ?? 0;
  int get neverAnswered => json['neverAnswered'] as int? ?? 0;
  int get endedByCustomer => json['endedByCustomer'] as int? ?? 0;
}

class SupportAdminStat {
  const SupportAdminStat(this.json);
  final Map<String, dynamic> json;

  String get name => json['name'] as String? ?? 'Admin';
  AdminLevel get level => AdminLevel.fromApi(json['level'] as String? ?? 'SUPPORT');
  bool get onDuty => json['onDuty'] as bool? ?? false;
  bool get online => json['online'] as bool? ?? false;
  int get openNow => json['openNow'] as int? ?? 0;
  int get firstReplies => json['firstReplies'] as int? ?? 0;
  int get resolved => json['resolved'] as int? ?? 0;
  double? get medianFirstResponseMinutes => _num(json['medianFirstResponseMinutes']);
  double? get averageRating => _num(json['averageRating']);
  int get ratings => json['ratings'] as int? ?? 0;
}

class SupportRatingEntry {
  const SupportRatingEntry(this.json);
  final Map<String, dynamic> json;

  int get rating => json['rating'] as int? ?? 0;
  String? get comment => json['comment'] as String?;
  SupportTopic? get topic => SupportTopic.fromApi(json['topic']);
  String? get adminName => json['adminName'] as String?;
  DateTime? get ratedAt => json['ratedAt'] != null ? DateTime.parse(json['ratedAt'] as String) : null;
}

/// `GET /support/metrics?days=` — the super-admin support dashboard.
class SupportMetrics {
  const SupportMetrics(this.json);
  final Map<String, dynamic> json;

  int get days => json['days'] as int? ?? 30;
  Map<String, dynamic> get _live => json['live'] as Map<String, dynamic>? ?? const {};
  int get waiting => _live['waiting'] as int? ?? 0;
  double? get oldestWaitMinutes => _num(_live['oldestWaitMinutes']);
  int get adminsAvailable => _live['adminsAvailable'] as int? ?? 0;
  int get openAssigned => _live['openAssigned'] as int? ?? 0;
  SupportTotals get totals => SupportTotals(json['totals'] as Map<String, dynamic>? ?? const {});

  List<({String label, SupportTotals totals})> get byTopic => [
    for (final t in (json['byTopic'] as List? ?? const []).cast<Map<String, dynamic>>())
      (label: SupportTopic.fromApi(t['topic'])?.label ?? 'Not specified', totals: SupportTotals(t)),
  ];
  List<SupportAdminStat> get byAdmin =>
      (json['byAdmin'] as List? ?? const []).cast<Map<String, dynamic>>().map(SupportAdminStat.new).toList();
  List<int> get byHour => (json['byHour'] as List? ?? const []).cast<int>();
  List<int> get byWeekday => (json['byWeekday'] as List? ?? const []).cast<int>();
  List<({DateTime date, int conversations, int resolved})> get byDay => [
    for (final d in (json['byDay'] as List? ?? const []).cast<Map<String, dynamic>>())
      (date: DateTime.parse(d['date'] as String), conversations: d['conversations'] as int? ?? 0, resolved: d['resolved'] as int? ?? 0),
  ];
  List<SupportRatingEntry> get recentRatings =>
      (json['recentRatings'] as List? ?? const []).cast<Map<String, dynamic>>().map(SupportRatingEntry.new).toList();
}
