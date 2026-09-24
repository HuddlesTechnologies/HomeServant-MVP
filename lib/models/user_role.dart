import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// The Figma prototype mirrors the same screens for both audiences: a warm
/// navy theme for tenants ("Looking for a Home?") and a dark brown theme
/// for landlords ("Register as a Landlord"). [vendor] is a third account
/// kind (a marketplace shop) that shares this app's auth/session system
/// but never renders through this theming — the Marketplace has its own
/// separate styling and never routes through the tenant/landlord
/// dashboard, so [background]/[accent]/etc. below are never actually
/// read for a vendor; they're only defined so this enum stays safe to use
/// anywhere a `UserRole` is expected.
enum UserRole {
  tenant,
  landlord,
  vendor,
  admin;

  bool get isLandlord => this == UserRole.landlord;
  bool get isVendor => this == UserRole.vendor;
  bool get isAdmin => this == UserRole.admin;

  /// Background colour of every themed screen for this role. Landlord
  /// screens use the light sand brand colour; tenant screens stay navy.
  Color get background => isLandlord ? AppColors.landlordSand : AppColors.navy;

  /// Colour used for primary button fills. Stays dark for both roles since
  /// every button here pairs it with hardcoded white button text.
  Color get accent => isLandlord ? AppColors.navy : AppColors.gold;

  /// Colour used for primary text / headings drawn on [background]. Tenant's
  /// background is dark navy, so it stays white; landlord's background is
  /// light sand, so it uses a near-black brown to stay legible.
  Color get foreground => isLandlord ? AppColors.landlordText : AppColors.white;

  /// Colour for emphasised text/links drawn directly on [background] (e.g.
  /// "Sign Up", "Resend OTP") — distinct from [foreground] so it still reads
  /// as a highlight, and distinct from [accent] because that one has to stay
  /// dark for button-fill contrast. Landlord's light sand background needs a
  /// dark highlight, so it reuses the brand's landlord brown; tenant's dark
  /// navy background keeps the gold highlight.
  Color get emphasis => isLandlord ? AppColors.landlordBrown : AppColors.gold;

  /// Only meant for the tenant/landlord auth screens' own copy, where
  /// this enum is never actually [vendor]/[admin] — see AdminUsersTab/
  /// AdminUserDetailScreen for a label that covers all four roles.
  String get label => isLandlord ? 'Landlord' : 'Tenant';

  /// Covers every role — for admin-console screens that display a
  /// vendor's or admin's own role rather than picking auth-screen copy.
  String get adminLabel => switch (this) {
    UserRole.tenant => 'Tenant',
    UserRole.landlord => 'Landlord',
    UserRole.vendor => 'Vendor',
    UserRole.admin => 'Admin',
  };
}
