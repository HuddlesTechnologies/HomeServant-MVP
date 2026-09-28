/// Platform Controls (backend PlatformSettingsService) with the numbers
/// that show what each switch affects.
class PlatformSettings {
  const PlatformSettings({
    required this.requireVerifiedLandlords,
    required this.payUnverifiedLandlords,
    this.heldPayoutCount = 0,
    this.heldPayoutKobo = 0,
    this.heldPayoutLandlords = 0,
    required this.totalListings,
    required this.unverifiedListings,
    required this.verifiedLandlords,
    required this.landlordsWithListings,
    this.updatedAt,
    this.updatedByName,
    this.maxListingImageChanges = 3,
    this.listingImageLockDays = 14,
    this.featuredListingFeeNaira = 5000,
    this.featuredListingDays = 7,
    this.promotedSlotEvery = 3,
  });

  /// Paid "Featured" ads: price (naira) and how long one runs.
  final int featuredListingFeeNaira;
  final int featuredListingDays;

  /// Fairness: one promoted listing in every N search results.
  final int promotedSlotEvery;

  /// How many times a landlord may change a listing's photos before they
  /// lock, and for how many days.
  final int maxListingImageChanges;
  final int listingImageLockDays;

  final bool requireVerifiedLandlords;

  /// On: unverified landlords are paid as normal. Off: their payouts are
  /// held until they're verified.
  final bool payUnverifiedLandlords;

  /// Payouts currently held because the landlord isn't verified.
  final int heldPayoutCount;
  final int heldPayoutKobo;
  final int heldPayoutLandlords;
  final int totalListings;
  final int unverifiedListings;
  final int verifiedLandlords;
  final int landlordsWithListings;
  final DateTime? updatedAt;
  final String? updatedByName;

  factory PlatformSettings.fromApi(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    final by = json['updatedBy'] as Map<String, dynamic>?;
    final held = json['heldPayouts'] as Map<String, dynamic>? ?? const {};
    return PlatformSettings(
      requireVerifiedLandlords: json['requireVerifiedLandlords'] as bool? ?? false,
      payUnverifiedLandlords: json['payUnverifiedLandlords'] as bool? ?? true,
      heldPayoutCount: held['count'] as int? ?? 0,
      heldPayoutKobo: held['totalKobo'] as int? ?? 0,
      heldPayoutLandlords: held['landlords'] as int? ?? 0,
      totalListings: stats['totalListings'] as int? ?? 0,
      unverifiedListings: stats['unverifiedListings'] as int? ?? 0,
      verifiedLandlords: stats['verifiedLandlords'] as int? ?? 0,
      landlordsWithListings: stats['landlordsWithListings'] as int? ?? 0,
      maxListingImageChanges: json['maxListingImageChanges'] as int? ?? 3,
      listingImageLockDays: json['listingImageLockDays'] as int? ?? 14,
      featuredListingFeeNaira: json['featuredListingFeeNaira'] as int? ?? 5000,
      featuredListingDays: json['featuredListingDays'] as int? ?? 7,
      promotedSlotEvery: json['promotedSlotEvery'] as int? ?? 3,
      updatedAt: json['updatedAt'] is String ? DateTime.tryParse(json['updatedAt'] as String)?.toLocal() : null,
      updatedByName: by == null ? null : ((by['fullName'] as String?)?.trim().isNotEmpty == true ? by['fullName'] as String : by['email'] as String?),
    );
  }
}
