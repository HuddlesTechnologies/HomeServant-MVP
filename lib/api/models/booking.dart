import '../../features/dashboard/models/property.dart';

/// PENDING → ACCEPTED (Shortlet only: booking itself accepted, landlord's
/// pre-payment approval) → PAID (Shortlet: charged, released automatically)
/// — vs a non-Shortlet rental, which now charges immediately on creation
/// (no PENDING/ACCEPTED wait) and instead moves PAID_AWAITING_INSPECTION →
/// INSPECTION_PROPOSED (tenant proposed a date) → INSPECTION_CONFIRMED
/// (landlord accepted that date) → MOVED_IN (released to landlord, lease
/// started) — or DECLINED (landlord's outright rejection, full refund, no
/// fee) / REFUNDED (tenant-initiated refund, 0.2% fee withheld) at any
/// point before MOVED_IN.
enum BookingStatus {
  pending,
  accepted,
  paid,
  paidAwaitingInspection,
  inspectionProposed,
  inspectionConfirmed,
  movedIn,
  declined,
  refunded,
}

/// [BookingStatus] from the server's `Booking.status` (e.g. on a chat's
/// inspection, see ChatInspection).
BookingStatus bookingStatusFromApi(String value) => _statusFromApi(value);

BookingStatus _statusFromApi(String value) => switch (value) {
  'ACCEPTED' => BookingStatus.accepted,
  'PAID' => BookingStatus.paid,
  'PAID_AWAITING_INSPECTION' => BookingStatus.paidAwaitingInspection,
  'INSPECTION_PROPOSED' => BookingStatus.inspectionProposed,
  'INSPECTION_CONFIRMED' => BookingStatus.inspectionConfirmed,
  'MOVED_IN' => BookingStatus.movedIn,
  'DECLINED' => BookingStatus.declined,
  'REFUNDED' => BookingStatus.refunded,
  _ => BookingStatus.pending,
};

/// Mirrors the backend's `Gender` enum (`MALE`/`FEMALE`/`OTHER`) as it
/// appears on a booking's embedded tenant. Named distinctly from any
/// account-profile-editing screen's own copy of the same backend enum
/// (rather than sharing a single `Gender` type across both) so this file
/// and that one can evolve independently without an ambiguous-import
/// conflict wherever both end up imported together (e.g. AppState).
enum TenantGender { male, female, other }

TenantGender? _genderFromApi(String? value) => switch (value) {
  'MALE' => TenantGender.male,
  'FEMALE' => TenantGender.female,
  'OTHER' => TenantGender.other,
  _ => null,
};

extension TenantGenderLabel on TenantGender {
  String get label => switch (this) {
    TenantGender.male => 'Male',
    TenantGender.female => 'Female',
    TenantGender.other => 'Other',
  };
}

/// Mirrors the backend's `MaritalStatus` enum
/// (`SINGLE`/`MARRIED`/`DIVORCED`/`WIDOWED`) — see [TenantGender]'s doc
/// comment for why this is a distinct type rather than shared.
enum TenantMaritalStatus { single, married, divorced, widowed }

TenantMaritalStatus? _maritalStatusFromApi(String? value) => switch (value) {
  'SINGLE' => TenantMaritalStatus.single,
  'MARRIED' => TenantMaritalStatus.married,
  'DIVORCED' => TenantMaritalStatus.divorced,
  'WIDOWED' => TenantMaritalStatus.widowed,
  _ => null,
};

extension TenantMaritalStatusLabel on TenantMaritalStatus {
  String get label => switch (this) {
    TenantMaritalStatus.single => 'Single',
    TenantMaritalStatus.married => 'Married',
    TenantMaritalStatus.divorced => 'Divorced',
    TenantMaritalStatus.widowed => 'Widowed',
  };
}

/// Mirrors a `Booking` row from `GET /bookings/mine` / `GET
/// /bookings/landlord` (see backend/src/bookings/bookings.service.ts),
/// with its related [Property] embedded the same way the API includes it.
class Booking {
  const Booking({
    required this.id,
    required this.property,
    required this.status,
    required this.createdAt,
    this.tenantId,
    this.tenantName,
    this.tenantEmail,
    this.tenantPhone,
    this.tenantVerified = false,
    this.refundedByHomeServant = false,
    this.landlordPaid = false,
    this.agreementCreatedAt,
    this.landlordFeedClearedAt,
    this.tenantProfilePhotoUrl,
    this.tenantGender,
    this.tenantOccupation,
    this.tenantBio,
    this.tenantHobbies = const [],
    this.tenantMaritalStatus,
    this.tenantDateOfBirth,
    this.requestedDate,
    this.message,
    this.nights,
    this.inspectionConfirmedAt,
    this.priceSnapshot,
    this.priceUnitSnapshot,
    this.leaseStartDate,
    this.leaseEndDate,
    this.lastPaidAt,
    this.payingMonthly = false,
    this.monthlyRent,
    this.rentPaidThrough,
  });

  /// Paying this rental month by month (the landlord allows it): the first
  /// month was paid up front; each later month is paid from the booking.
  final bool payingMonthly;

  /// The agreed monthly rent, in naira.
  final int? monthlyRent;

  /// How far the monthly rent is paid (monthly plan, after move-in).
  final DateTime? rentPaidThrough;

  /// Months of the current lease still to pay (monthly plan, moved in).
  bool get hasMonthsLeftToPay =>
      payingMonthly &&
      status == BookingStatus.movedIn &&
      rentPaidThrough != null &&
      leaseEndDate != null &&
      rentPaidThrough!.isBefore(leaseEndDate!);

  /// The next month's rent is overdue.
  bool get monthlyRentOverdue => hasMonthsLeftToPay && rentPaidThrough!.isBefore(DateTime.now());

  /// The next month can be paid now (from 7 days before it's due).
  bool get canPayNextMonth =>
      hasMonthsLeftToPay && rentPaidThrough!.difference(DateTime.now()) <= const Duration(days: 7);

  final String id;
  final Property property;
  final BookingStatus status;
  final DateTime createdAt;
  final String? tenantId;
  final String? tenantName;

  /// Only present on a landlord's own view of a booking (`GET
  /// /bookings/landlord`) — the fields below back "View Tenant Profile".
  final String? tenantEmail;

  /// Only sent once this tenant has paid for the landlord's property.
  final String? tenantPhone;

  /// HomeServant has verified this tenant's identity.
  final bool tenantVerified;

  /// Refunded in full by a HomeServant admin (not the tenant's own refund).
  final bool refundedByHomeServant;

  /// The landlord has actually been paid for this booking (move-in
  /// confirmed, or a Shortlet's payout sent) — only then can the tenant
  /// rate the property. Tenant's own view only.
  final bool landlordPaid;

  /// When this booking's tenancy agreement was generated (at move-in), or
  /// null if it has none yet. Tenant's own view only.
  final DateTime? agreementCreatedAt;

  /// The landlord cleared this request from their home feed. It isn't
  /// declined: it still shows in Bookings and counts as waiting.
  final DateTime? landlordFeedClearedAt;
  final String? tenantProfilePhotoUrl;
  final TenantGender? tenantGender;
  final String? tenantOccupation;

  /// The tenant's booking profile — a little background and their hobbies
  /// (landlord's view of a booking only).
  final String? tenantBio;
  final List<String> tenantHobbies;
  final TenantMaritalStatus? tenantMaritalStatus;
  final DateTime? tenantDateOfBirth;

  /// The tenant's requested/proposed date — for a Shortlet, the stay's
  /// start date; for a non-Shortlet booking in INSPECTION_PROPOSED or
  /// INSPECTION_CONFIRMED, the inspection date itself (cleared back to
  /// null if the landlord declines that date via `respondToInspection`).
  final DateTime? requestedDate;
  final String? message;

  /// Number of nights requested — only set (and only meaningful) for a
  /// Shortlet booking.
  final int? nights;

  /// When the landlord confirmed the tenant's proposed inspection date
  /// (non-Shortlet) — null until then. This is the confirmation
  /// timestamp itself, not the inspection date — see [requestedDate] for
  /// the actual date.
  final DateTime? inspectionConfirmedAt;

  /// The property's price/priceUnit at the moment this booking was made —
  /// the property's own price can change later, so this is what's actually
  /// charged (same snapshot convention as `MarketplaceOrderItem`).
  final int? priceSnapshot;
  final String? priceUnitSnapshot;

  /// Set once the booking reaches MOVED_IN — the lease term, computed from
  /// the property's configured rent duration.
  final DateTime? leaseStartDate;
  final DateTime? leaseEndDate;

  /// Only present on a landlord's own view (`GET /bookings/landlord`) —
  /// when the most recent successful charge on this booking actually
  /// landed (`Payment.paidAt`), not just when the booking was created. Null
  /// if nothing has been charged yet, or on a tenant's own view (`GET
  /// /bookings/mine` doesn't compute this).
  final DateTime? lastPaidAt;

  bool get isShortlet => property.category == 'Shortlet';

  /// When a shortlet stay ends: its start date plus the nights booked (or
  /// the lease end, where one was recorded). Null if unknown or not a
  /// shortlet.
  DateTime? get shortletStayEnd {
    if (!isShortlet) return null;
    if (leaseEndDate != null) return leaseEndDate;
    final start = requestedDate;
    if (start == null || nights == null) return null;
    return start.add(Duration(days: nights!));
  }

  /// Computed client-side from [tenantDateOfBirth] — null if that's null.
  int? get tenantAge {
    final dob = tenantDateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  factory Booking.fromApi(Map<String, dynamic> json) {
    final tenant = json['tenant'] as Map<String, dynamic>?;
    return Booking(
      id: json['id'] as String,
      property: Property.fromApi(json['property'] as Map<String, dynamic>),
      status: _statusFromApi(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      tenantId: tenant?['id'] as String? ?? json['tenantId'] as String?,
      tenantName: tenant?['fullName'] as String?,
      tenantEmail: tenant?['email'] as String?,
      tenantPhone: tenant?['phoneNumber'] as String?,
      tenantVerified: (tenant?['identityVerification'] as Map<String, dynamic>?)?['status'] == 'APPROVED',
      refundedByHomeServant: json['refundedByHomeServant'] as bool? ?? false,
      landlordPaid: json['landlordPaid'] as bool? ?? false,
      agreementCreatedAt: _parseDate((json['tenancyAgreement'] as Map<String, dynamic>?)?['generatedAt']),
      landlordFeedClearedAt: _parseDate(json['landlordFeedClearedAt']),
      tenantProfilePhotoUrl: tenant?['profilePhotoUrl'] as String?,
      tenantGender: _genderFromApi(tenant?['gender'] as String?),
      tenantOccupation: tenant?['occupation'] as String?,
      tenantBio: tenant?['bio'] as String?,
      tenantHobbies: (tenant?['hobbies'] as List?)?.cast<String>() ?? const [],
      tenantMaritalStatus: _maritalStatusFromApi(tenant?['maritalStatus'] as String?),
      tenantDateOfBirth: _parseDate(tenant?['dateOfBirth']),
      requestedDate: _parseDate(json['requestedDate']),
      message: json['message'] as String?,
      nights: json['nights'] as int?,
      inspectionConfirmedAt: _parseDate(json['inspectionConfirmedAt']),
      priceSnapshot: json['priceSnapshot'] as int?,
      priceUnitSnapshot: json['priceUnitSnapshot'] as String?,
      leaseStartDate: _parseDate(json['leaseStartDate']),
      leaseEndDate: _parseDate(json['leaseEndDate']),
      lastPaidAt: _parseDate(json['lastPaidAt']),
      payingMonthly: json['paymentPlan'] == 'MONTHLY',
      monthlyRent: json['monthlyRent'] as int?,
      rentPaidThrough: _parseDate(json['rentPaidThrough']),
    );
  }

  /// In the device's local time: the server sends UTC instants, and an
  /// inspection date chosen as "2 Oct, 10:00" should read back that way.
  static DateTime? _parseDate(dynamic value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;
}
