/// A rent payment that needs an admin: a payout to a landlord that hasn't
/// gone out, or a refund to a tenant that failed — see backend
/// PaymentsService.stuckPayouts.
enum StuckPaymentKind { payout, refund }

class StuckPayment {
  const StuckPayment({
    required this.kind,
    required this.paymentId,
    required this.amountKobo,
    required this.reason,
    required this.canRetry,
    required this.canRetryRefund,
    required this.canRefundTenant,
    required this.inProgress,
    this.canPause = false,
    this.canResume = false,
    this.canCancel = false,
    required this.landlordId,
    required this.landlordName,
    required this.landlordVerified,
    this.landlordBank,
    this.landlordAccountLast4,
    this.propertyTitle,
    this.tenantName,
    this.lastError,
    this.requestedBy,
    this.attempts = 0,
    this.since,
    this.pausedAt,
    this.pauseReason,
  });

  final StuckPaymentKind kind;
  final String paymentId;
  final int amountKobo;

  /// AWAITING_VERIFICATION, NO_BANK_ACCOUNT, FAILED, READY, PAUSED,
  /// REFUND_FAILED.
  final String reason;
  final bool canRetry;
  final bool canRetryRefund;
  final bool canRefundTenant;
  final bool inProgress;

  /// Payout actions: pause it (nothing is sent until it's resumed), resume
  /// it, or cancel it for good (the landlord is never paid it).
  final bool canPause;
  final bool canResume;
  final bool canCancel;
  final String landlordId;
  final String landlordName;
  final bool landlordVerified;
  final String? landlordBank;
  final String? landlordAccountLast4;
  final String? propertyTitle;
  final String? tenantName;
  final String? lastError;

  /// For a failed refund: TENANT, LANDLORD or ADMIN.
  final String? requestedBy;
  final int attempts;
  final DateTime? since;

  /// Set while an admin has this payout paused, with their note.
  final DateTime? pausedAt;
  final String? pauseReason;

  String get reasonLabel => switch (reason) {
    'AWAITING_VERIFICATION' => 'Waiting for landlord verification',
    'NO_BANK_ACCOUNT' => 'No bank account on file',
    'READY' => 'Ready to pay',
    'PAUSED' => 'Paused by an admin',
    'REFUND_FAILED' => 'Refund to tenant failed',
    _ => 'Transfer failed',
  };

  factory StuckPayment.fromApi(Map<String, dynamic> json) {
    final landlord = json['landlord'] as Map<String, dynamic>;
    final property = json['property'] as Map<String, dynamic>?;
    final tenant = json['tenant'] as Map<String, dynamic>?;
    DateTime? date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return StuckPayment(
      kind: json['kind'] == 'REFUND' ? StuckPaymentKind.refund : StuckPaymentKind.payout,
      paymentId: json['paymentId'] as String,
      amountKobo: json['amountKobo'] as int? ?? 0,
      reason: json['reason'] as String? ?? 'FAILED',
      canRetry: json['canRetry'] as bool? ?? false,
      canRetryRefund: json['canRetryRefund'] as bool? ?? false,
      canRefundTenant: json['canRefundTenant'] as bool? ?? false,
      inProgress: json['inProgress'] as bool? ?? false,
      canPause: json['canPause'] as bool? ?? false,
      canResume: json['canResume'] as bool? ?? false,
      canCancel: json['canCancel'] as bool? ?? false,
      landlordId: landlord['id'] as String,
      landlordName: landlord['name'] as String? ?? 'Landlord',
      landlordVerified: landlord['verified'] as bool? ?? false,
      landlordBank: landlord['bankName'] as String?,
      landlordAccountLast4: landlord['accountLast4'] as String?,
      propertyTitle: property?['title'] as String?,
      tenantName: tenant == null ? null : ((tenant['fullName'] as String?)?.trim().isNotEmpty == true ? tenant['fullName'] as String : tenant['email'] as String?),
      lastError: json['lastError'] as String?,
      requestedBy: json['requestedBy'] as String?,
      attempts: json['attempts'] as int? ?? 0,
      since: date(json['heldSince']),
      pausedAt: date(json['pausedAt']),
      pauseReason: json['pauseReason'] as String?,
    );
  }
}
