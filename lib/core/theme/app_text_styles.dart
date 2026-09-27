import 'package:flutter/material.dart';

/// Givonic is the app's general-purpose text face; Quity is reserved for
/// headings only.
class AppTextStyles {
  AppTextStyles._();

  static const String headingFont = 'Quity';
  static const String bodyFont = 'Givonic';

  /// Givonic and Quity have no ₦, dashes, bullets, ellipsis or arrows.
  /// Without a bundled fallback, Flutter web downloads one from
  /// fonts.gstatic.com while the page runs, and those characters render
  /// blank whenever that download is slow or blocked.
  static const List<String> fallbackFonts = ['HSFallback'];

  static TextStyle display({required Color color, double size = 34}) =>
      TextStyle(
        fontFamily: bodyFont,
        fontFamilyFallback: fallbackFonts,
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.05,
      );

  static TextStyle heading({required Color color, double size = 26}) =>
      TextStyle(
        fontFamily: headingFont,
        fontFamilyFallback: fallbackFonts,
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w500,
      );

  static TextStyle body({
    required Color color,
    double size = 15,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: bodyFont,
    fontFamilyFallback: fallbackFonts,
    color: color,
    fontSize: size,
    fontWeight: weight,
  );

  static TextStyle button({required Color color, double size = 16}) =>
      TextStyle(
        fontFamily: bodyFont,
        fontFamilyFallback: fallbackFonts,
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w700,
      );
}
