/// Identity documents given at signup, and their review — see backend
/// VerificationService.
enum VerificationStatus {
  incomplete,
  pending,
  approved,
  rejected;

  static VerificationStatus? fromApi(String? value) => switch (value) {
    'INCOMPLETE' => VerificationStatus.incomplete,
    'PENDING' => VerificationStatus.pending,
    'APPROVED' => VerificationStatus.approved,
    'REJECTED' => VerificationStatus.rejected,
    _ => null,
  };

  String get apiValue => name.toUpperCase();

  String get label => switch (this) {
    VerificationStatus.incomplete => 'Incomplete',
    VerificationStatus.pending => 'Awaiting review',
    VerificationStatus.approved => 'Verified',
    VerificationStatus.rejected => 'Rejected',
  };
}

/// The means of ID offered at signup, with the API value for each.
enum IdDocumentType {
  nin('NIN', 'NIN'),
  driversLicense('DRIVERS_LICENSE', "Driver's License"),
  votersCard('VOTERS_CARD', "Voter's Card"),
  passport('INTERNATIONAL_PASSPORT', 'International Passport');

  const IdDocumentType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static IdDocumentType? fromApi(String? value) {
    for (final t in values) {
      if (t.apiValue == value) return t;
    }
    return null;
  }

  static IdDocumentType? fromLabel(String? label) {
    for (final t in values) {
      if (t.label == label) return t;
    }
    return null;
  }
}

class VerificationPerson {
  const VerificationPerson({required this.id, required this.name, required this.email, this.phone, this.role});

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? role;

  factory VerificationPerson.fromApi(Map<String, dynamic> json) => VerificationPerson(
    id: json['id'] as String,
    name: (json['fullName'] as String?)?.trim().isNotEmpty == true ? json['fullName'] as String : (json['email'] as String? ?? 'User'),
    email: json['email'] as String? ?? '',
    phone: json['phoneNumber'] as String?,
    role: json['role'] as String?,
  );
}

DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

/// One row of the admin review queue (ID number masked).
class VerificationSummary {
  const VerificationSummary({
    required this.userId,
    required this.user,
    required this.status,
    this.idType,
    this.idNumberMasked,
    this.hasCertificate = false,
    this.hasDocument = false,
    this.submittedAt,
  });

  final String userId;
  final VerificationPerson user;
  final VerificationStatus status;
  final IdDocumentType? idType;
  final String? idNumberMasked;
  final bool hasCertificate;
  final bool hasDocument;
  final DateTime? submittedAt;

  factory VerificationSummary.fromApi(Map<String, dynamic> json) => VerificationSummary(
    userId: json['userId'] as String,
    user: VerificationPerson.fromApi(json['user'] as Map<String, dynamic>),
    status: VerificationStatus.fromApi(json['status'] as String?) ?? VerificationStatus.incomplete,
    idType: IdDocumentType.fromApi(json['idType'] as String?),
    idNumberMasked: json['idNumber'] as String?,
    hasCertificate: json['hasCertificate'] as bool? ?? false,
    hasDocument: json['hasDocument'] as bool? ?? false,
    submittedAt: _date(json['submittedAt']),
  );
}

/// The full record for review: whole ID number and signed file links that
/// expire after [linksExpireInSeconds].
class VerificationDetail {
  const VerificationDetail({
    required this.status,
    this.idType,
    this.idNumber,
    this.certificateUrl,
    this.certificateIsPdf = false,
    this.documentUrl,
    this.documentIsPdf = false,
    this.submittedAt,
    this.reviewedBy,
    this.reviewNote,
    this.reviewedAt,
    this.linksExpireInSeconds = 600,
  });

  /// Null when the user never submitted anything.
  final VerificationStatus? status;
  final IdDocumentType? idType;
  final String? idNumber;
  final String? certificateUrl;
  final bool certificateIsPdf;
  final String? documentUrl;
  final bool documentIsPdf;
  final DateTime? submittedAt;
  final VerificationPerson? reviewedBy;
  final String? reviewNote;
  final DateTime? reviewedAt;
  final int linksExpireInSeconds;

  factory VerificationDetail.fromApi(Map<String, dynamic> json) {
    final reviewer = json['reviewedBy'] as Map<String, dynamic>?;
    return VerificationDetail(
      status: VerificationStatus.fromApi(json['status'] as String?),
      idType: IdDocumentType.fromApi(json['idType'] as String?),
      idNumber: json['idNumber'] as String?,
      certificateUrl: json['certificateUrl'] as String?,
      certificateIsPdf: json['certificateIsPdf'] as bool? ?? false,
      documentUrl: json['documentUrl'] as String?,
      documentIsPdf: json['documentIsPdf'] as bool? ?? false,
      submittedAt: _date(json['submittedAt']),
      reviewedBy: reviewer == null ? null : VerificationPerson.fromApi(reviewer),
      reviewNote: json['reviewNote'] as String?,
      reviewedAt: _date(json['reviewedAt']),
      linksExpireInSeconds: json['linksExpireInSeconds'] as int? ?? 600,
    );
  }
}
