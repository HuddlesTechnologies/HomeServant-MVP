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

/// What the body that issued an ID said about it when HomeServant looked
/// the number up — see the backend's IdCheckProvider. [match] is the only
/// outcome that verifies an account on its own (tenants only).
enum IdCheckStatus {
  notRun('NOT_RUN', 'Not checked'),
  match('MATCH', 'Confirmed by the issuing body'),
  mismatch('MISMATCH', 'Registered to a different name'),
  notFound('NOT_FOUND', 'No record of this number'),
  unsupported('UNSUPPORTED', 'Not checked automatically'),
  error('ERROR', "Couldn't be checked");

  const IdCheckStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// True when the registry gave a real answer about the ID rather than
  /// the check failing to happen — the difference between "this is wrong"
  /// and "we don't know", which is what a reviewer needs to tell apart.
  bool get isAnswer => this == match || this == mismatch || this == notFound;

  static IdCheckStatus fromApi(String? value) {
    for (final status in values) {
      if (status.apiValue == value) return status;
    }
    return IdCheckStatus.notRun;
  }
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
    this.idCheckStatus = IdCheckStatus.notRun,
    this.hasCertificate = false,
    this.hasDocument = false,
    this.submittedAt,
    this.autoApproved = false,
  });

  final String userId;
  final VerificationPerson user;
  final VerificationStatus status;
  final IdDocumentType? idType;
  final String? idNumberMasked;
  final IdCheckStatus idCheckStatus;
  final bool hasCertificate;
  final bool hasDocument;
  final DateTime? submittedAt;
  /// Verified by a clean automated check rather than by a moderator.
  final bool autoApproved;

  factory VerificationSummary.fromApi(Map<String, dynamic> json) => VerificationSummary(
    userId: json['userId'] as String,
    user: VerificationPerson.fromApi(json['user'] as Map<String, dynamic>),
    status: VerificationStatus.fromApi(json['status'] as String?) ?? VerificationStatus.incomplete,
    idType: IdDocumentType.fromApi(json['idType'] as String?),
    idNumberMasked: json['idNumber'] as String?,
    idCheckStatus: IdCheckStatus.fromApi(json['idCheckStatus'] as String?),
    hasCertificate: json['hasCertificate'] as bool? ?? false,
    hasDocument: json['hasDocument'] as bool? ?? false,
    submittedAt: _date(json['submittedAt']),
    autoApproved: json['autoApproved'] as bool? ?? false,
  );
}

/// The full record for review: whole ID number and signed file links that
/// expire after [linksExpireInSeconds].
class VerificationDetail {
  const VerificationDetail({
    required this.status,
    this.idType,
    this.idNumber,
    this.idCheckStatus = IdCheckStatus.notRun,
    this.idCheckProvider,
    this.idCheckReference,
    this.idCheckName,
    this.idCheckDetail,
    this.idCheckedAt,
    this.autoApproved = false,
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
  final IdCheckStatus idCheckStatus;
  /// Who answered ("prembly"), and their own reference for the check.
  final String? idCheckProvider;
  final String? idCheckReference;
  /// The name the issuing body holds against this number — the thing
  /// compared against the name on the account.
  final String? idCheckName;
  /// The provider's own one-line message about the check.
  final String? idCheckDetail;
  final DateTime? idCheckedAt;
  /// Verified by the check itself, with no moderator involved — which is
  /// why [reviewedBy] is null on an approved submission.
  final bool autoApproved;
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
      idCheckStatus: IdCheckStatus.fromApi(json['idCheckStatus'] as String?),
      idCheckProvider: json['idCheckProvider'] as String?,
      idCheckReference: json['idCheckReference'] as String?,
      idCheckName: json['idCheckName'] as String?,
      idCheckDetail: json['idCheckDetail'] as String?,
      idCheckedAt: _date(json['idCheckedAt']),
      autoApproved: json['autoApproved'] as bool? ?? false,
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
