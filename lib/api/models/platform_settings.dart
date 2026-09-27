/// Platform Controls (backend PlatformSettingsService) with the numbers
/// that show what each switch affects.
class PlatformSettings {
  const PlatformSettings({
    required this.requireVerifiedLandlords,
    required this.totalListings,
    required this.unverifiedListings,
    required this.verifiedLandlords,
    required this.landlordsWithListings,
    this.updatedAt,
    this.updatedByName,
  });

  final bool requireVerifiedLandlords;
  final int totalListings;
  final int unverifiedListings;
  final int verifiedLandlords;
  final int landlordsWithListings;
  final DateTime? updatedAt;
  final String? updatedByName;

  factory PlatformSettings.fromApi(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? const {};
    final by = json['updatedBy'] as Map<String, dynamic>?;
    return PlatformSettings(
      requireVerifiedLandlords: json['requireVerifiedLandlords'] as bool? ?? false,
      totalListings: stats['totalListings'] as int? ?? 0,
      unverifiedListings: stats['unverifiedListings'] as int? ?? 0,
      verifiedLandlords: stats['verifiedLandlords'] as int? ?? 0,
      landlordsWithListings: stats['landlordsWithListings'] as int? ?? 0,
      updatedAt: json['updatedAt'] is String ? DateTime.tryParse(json['updatedAt'] as String)?.toLocal() : null,
      updatedByName: by == null ? null : ((by['fullName'] as String?)?.trim().isNotEmpty == true ? by['fullName'] as String : by['email'] as String?),
    );
  }
}
