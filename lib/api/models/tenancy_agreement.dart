/// Mirrors the persisted `TenancyAgreement` row returned by `GET
/// /bookings/:id/tenancy-agreement` — generated once, server-side, on
/// move-in. Replaces the old client-side fabrication in
/// `tenancy_agreement_content.dart`, which invented a lease end date and
/// hardcoded the landlord's contact details.
class TenancyAgreement {
  const TenancyAgreement({
    required this.propertyTitle,
    required this.propertyLocation,
    required this.propertyState,
    required this.rentAmount,
    required this.priceUnit,
    required this.leaseStartDate,
    required this.leaseEndDate,
    required this.landlordName,
    required this.tenantName,
    required this.generatedAt,
    this.landlordEmail,
    this.landlordPhone,
    this.tenantEmail,
    this.tenantPhone,
  });

  final String propertyTitle;
  final String propertyLocation;
  final String propertyState;
  final int rentAmount;
  final String priceUnit;
  final DateTime leaseStartDate;
  final DateTime leaseEndDate;
  final String landlordName;
  final String? landlordEmail;
  final String? landlordPhone;
  final String tenantName;
  final String? tenantEmail;
  final String? tenantPhone;
  final DateTime generatedAt;

  factory TenancyAgreement.fromApi(Map<String, dynamic> json) => TenancyAgreement(
    propertyTitle: json['propertyTitle'] as String,
    propertyLocation: json['propertyLocation'] as String,
    propertyState: json['propertyState'] as String,
    rentAmount: (json['rentAmount'] as num).toInt(),
    priceUnit: json['priceUnit'] as String,
    leaseStartDate: DateTime.parse(json['leaseStartDate'] as String),
    leaseEndDate: DateTime.parse(json['leaseEndDate'] as String),
    landlordName: json['landlordName'] as String,
    landlordEmail: json['landlordEmail'] as String?,
    landlordPhone: json['landlordPhone'] as String?,
    tenantName: json['tenantName'] as String,
    tenantEmail: json['tenantEmail'] as String?,
    tenantPhone: json['tenantPhone'] as String?,
    generatedAt: DateTime.parse(json['generatedAt'] as String),
  );
}
