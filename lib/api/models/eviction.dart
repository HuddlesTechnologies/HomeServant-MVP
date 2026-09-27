/// A landlord's request to end a tenancy early — see backend
/// EvictionsService. Nothing happens to the tenancy until a super admin
/// approves it.
enum EvictionStatus {
  pending,
  approved,
  rejected,
  cancelled;

  static EvictionStatus fromApi(String value) => switch (value) {
    'APPROVED' => EvictionStatus.approved,
    'REJECTED' => EvictionStatus.rejected,
    'CANCELLED' => EvictionStatus.cancelled,
    _ => EvictionStatus.pending,
  };

  String get label => switch (this) {
    EvictionStatus.pending => 'Under review',
    EvictionStatus.approved => 'Approved',
    EvictionStatus.rejected => 'Rejected',
    EvictionStatus.cancelled => 'Withdrawn',
  };
}

class EvictionParty {
  const EvictionParty({required this.id, required this.name, this.email, this.phone});

  final String id;
  final String name;
  final String? email;
  final String? phone;

  factory EvictionParty.fromApi(Map<String, dynamic> json) => EvictionParty(
    id: json['id'] as String,
    name: (json['fullName'] as String?)?.trim().isNotEmpty == true ? json['fullName'] as String : (json['email'] as String? ?? 'User'),
    email: json['email'] as String?,
    phone: json['phoneNumber'] as String?,
  );
}

class EvictionRequest {
  const EvictionRequest({
    required this.id,
    required this.bookingId,
    required this.propertyId,
    required this.propertyTitle,
    required this.propertyLocation,
    required this.landlord,
    required this.tenant,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.tenantResponse,
    this.tenantRespondedAt,
    this.reviewedBy,
    this.reviewNote,
    this.reviewedAt,
    this.leaseStartDate,
    this.leaseEndDate,
  });

  final String id;
  final String bookingId;
  final String propertyId;
  final String propertyTitle;
  final String propertyLocation;
  final EvictionParty landlord;
  final EvictionParty tenant;
  final String reason;
  final EvictionStatus status;
  final DateTime createdAt;
  final String? tenantResponse;
  final DateTime? tenantRespondedAt;
  final EvictionParty? reviewedBy;
  final String? reviewNote;
  final DateTime? reviewedAt;
  final DateTime? leaseStartDate;
  final DateTime? leaseEndDate;

  bool get isPending => status == EvictionStatus.pending;

  factory EvictionRequest.fromApi(Map<String, dynamic> json) {
    final booking = json['booking'] as Map<String, dynamic>;
    final property = booking['property'] as Map<String, dynamic>;
    DateTime? date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    final reviewer = json['reviewedBy'] as Map<String, dynamic>?;
    return EvictionRequest(
      id: json['id'] as String,
      bookingId: json['bookingId'] as String,
      propertyId: property['id'] as String,
      propertyTitle: property['title'] as String,
      propertyLocation: [property['location'], property['state']].whereType<String>().join(', '),
      landlord: EvictionParty.fromApi(json['landlord'] as Map<String, dynamic>),
      tenant: EvictionParty.fromApi(json['tenant'] as Map<String, dynamic>),
      reason: json['reason'] as String,
      status: EvictionStatus.fromApi(json['status'] as String),
      createdAt: date(json['createdAt']) ?? DateTime.now(),
      tenantResponse: json['tenantResponse'] as String?,
      tenantRespondedAt: date(json['tenantRespondedAt']),
      reviewedBy: reviewer == null ? null : EvictionParty.fromApi(reviewer),
      reviewNote: json['reviewNote'] as String?,
      reviewedAt: date(json['reviewedAt']),
      leaseStartDate: date(booking['leaseStartDate']),
      leaseEndDate: date(booking['leaseEndDate']),
    );
  }
}
