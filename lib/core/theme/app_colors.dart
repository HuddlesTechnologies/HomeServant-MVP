import 'package:flutter/material.dart';

/// Core palette lifted directly from the Home Servant Figma prototype.
class AppColors {
  AppColors._();

  static const Color navy = Color(0xFF132442);
  static const Color navyDark = Color(0xFF0D1A30);
  static const Color gold = Color(0xFFEDC47C);
  static const Color goldDark = Color(0xFFD9A94F);
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFFAF3E4);
  static const Color inputFieldGrey = Color(0xFF8C93A6);
  static const Color hintGrey = Color(0xFF7A7F8C);

  /// Warm brown, the landlord brand colour: emphasis and links on the
  /// landlord's [landlordSand] screens ([UserRole.emphasis]), and landlord
  /// or super-admin accents elsewhere.
  static const Color landlordBrown = Color(0xFF774C00);

  /// The three brand colours the "Theme" picker is allowed to recombine —
  /// navy, sand, and white. No other colours are introduced by any theme.
  static const Color sand = Color(0xFFF2CF8F);

  /// Landlord auth screens' background (login/signup).
  static const Color landlordSand = Color(0xFFF2CE8E);

  /// Primary text colour on landlord auth screens' light sand background —
  /// white doesn't contrast there, so this near-black brown stands in.
  static const Color landlordText = Color(0xFF291A00);
}
