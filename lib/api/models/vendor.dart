import 'package:flutter/material.dart';

enum MarketplaceCategory {
  furniture,
  homeAppliances,
  electronics,
  fittingsFixtures,
  decor,
  toolsEquipment,
  other,
}

extension MarketplaceCategoryApi on MarketplaceCategory {
  String get apiValue => switch (this) {
    MarketplaceCategory.furniture => 'FURNITURE',
    MarketplaceCategory.homeAppliances => 'HOME_APPLIANCES',
    MarketplaceCategory.electronics => 'ELECTRONICS',
    MarketplaceCategory.fittingsFixtures => 'FITTINGS_FIXTURES',
    MarketplaceCategory.decor => 'DECOR',
    MarketplaceCategory.toolsEquipment => 'TOOLS_EQUIPMENT',
    MarketplaceCategory.other => 'OTHER',
  };

  /// Matches the labels already shown across the vendor signup/product
  /// forms and the customer-facing category chips.
  String get label => switch (this) {
    MarketplaceCategory.furniture => 'Furniture',
    MarketplaceCategory.homeAppliances => 'Home Appliances',
    MarketplaceCategory.electronics => 'Electronics',
    MarketplaceCategory.fittingsFixtures => 'Fittings & Fixtures',
    MarketplaceCategory.decor => 'Décor',
    MarketplaceCategory.toolsEquipment => 'Tools & Equipment',
    MarketplaceCategory.other => 'Other',
  };

  static MarketplaceCategory fromApi(String value) => switch (value) {
    'FURNITURE' => MarketplaceCategory.furniture,
    'HOME_APPLIANCES' => MarketplaceCategory.homeAppliances,
    'ELECTRONICS' => MarketplaceCategory.electronics,
    'FITTINGS_FIXTURES' => MarketplaceCategory.fittingsFixtures,
    'DECOR' => MarketplaceCategory.decor,
    'TOOLS_EQUIPMENT' => MarketplaceCategory.toolsEquipment,
    _ => MarketplaceCategory.other,
  };

  static MarketplaceCategory fromLabel(String label) =>
      MarketplaceCategory.values.firstWhere((c) => c.label == label, orElse: () => MarketplaceCategory.other);

  IconData get icon => switch (this) {
    MarketplaceCategory.furniture => Icons.weekend_rounded,
    MarketplaceCategory.homeAppliances => Icons.ac_unit_rounded,
    MarketplaceCategory.electronics => Icons.tv_rounded,
    MarketplaceCategory.fittingsFixtures => Icons.plumbing_rounded,
    MarketplaceCategory.decor => Icons.image_rounded,
    MarketplaceCategory.toolsEquipment => Icons.handyman_rounded,
    MarketplaceCategory.other => Icons.inventory_2_rounded,
  };
}

const marketplaceCategoryLabels = [
  'Furniture',
  'Home Appliances',
  'Electronics',
  'Fittings & Fixtures',
  'Décor',
  'Tools & Equipment',
  'Other',
];

/// Admin moderation status — new vendors start [pending] and aren't shown
/// in the public Marketplace feed until an admin approves them (see
/// backend/src/marketplace-products/marketplace-products.service.ts).
/// Distinct from [VendorProfile.isActive], which is the separate
/// self-service pause/admin suspend toggle.
enum VendorApplicationStatus {
  pending,
  approved,
  rejected;

  String get apiValue => switch (this) {
    VendorApplicationStatus.pending => 'PENDING',
    VendorApplicationStatus.approved => 'APPROVED',
    VendorApplicationStatus.rejected => 'REJECTED',
  };

  String get label => switch (this) {
    VendorApplicationStatus.pending => 'Pending Review',
    VendorApplicationStatus.approved => 'Approved',
    VendorApplicationStatus.rejected => 'Rejected',
  };

  static VendorApplicationStatus fromApi(String value) => switch (value) {
    'APPROVED' => VendorApplicationStatus.approved,
    'REJECTED' => VendorApplicationStatus.rejected,
    _ => VendorApplicationStatus.pending,
  };
}

class VendorProfile {
  const VendorProfile({
    required this.id,
    required this.userId,
    required this.businessName,
    required this.category,
    required this.state,
    required this.isActive,
    required this.status,
    this.rejectionReason,
    this.rcNumber,
    this.logoUrl,
    this.bankCode,
    this.bankName,
    this.accountNumber,
    this.accountName,
  });

  final String id;
  final String userId;
  final String businessName;
  final MarketplaceCategory category;
  final String state;
  final bool isActive;
  final VendorApplicationStatus status;
  final String? rejectionReason;
  final String? rcNumber;
  final String? logoUrl;

  /// The vendor's payout account — mirrors [AppState.bankCode]/etc. on the
  /// landlord side. Only ever set via the server's Paystack-resolved
  /// response (see [VendorsRepository.update]); never trusted raw from a
  /// client-side text field.
  final String? bankCode;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;

  bool get hasPayoutDetails => accountNumber != null && accountNumber!.isNotEmpty;

  factory VendorProfile.fromApi(Map<String, dynamic> json) => VendorProfile(
    id: json['id'] as String,
    userId: json['userId'] as String,
    businessName: json['businessName'] as String,
    category: MarketplaceCategoryApi.fromApi(json['category'] as String),
    state: json['state'] as String,
    isActive: json['isActive'] as bool? ?? true,
    status: VendorApplicationStatus.fromApi(json['status'] as String? ?? 'APPROVED'),
    rejectionReason: json['rejectionReason'] as String?,
    rcNumber: json['rcNumber'] as String?,
    logoUrl: json['logoUrl'] as String?,
    bankCode: json['bankCode'] as String?,
    bankName: json['bankName'] as String?,
    accountNumber: json['accountNumber'] as String?,
    accountName: json['accountName'] as String?,
  );
}
