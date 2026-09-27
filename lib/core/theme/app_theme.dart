import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      // Bundled glyphs for ₦ — · … etc. on any text without its own style.
      fontFamilyFallback: AppTextStyles.fallbackFonts,
      scaffoldBackgroundColor: AppColors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        primary: AppColors.navy,
        secondary: AppColors.gold,
      ),
      textTheme: TextTheme(
        bodyMedium: AppTextStyles.body(color: AppColors.navy),
        // Button labels (TextButton, SnackBarAction, dialog actions) draw
        // from labelLarge. Left unset it had no font family and fell back
        // to Roboto fetched at runtime, which on web can render as nothing
        // (the same failure as the calendar's invisible OK button) — so
        // it's pinned to the bundled font. Buttons still take their colour
        // from their own foregroundColor.
        labelLarge: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600),
      ),
      // Every SnackBar: navy background, white text, gold action button —
      // explicit pairs rather than the seed-derived inverse colours, which
      // made action buttons (e.g. the admin console's "Turn on" for browser
      // pop-ups) close to invisible.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.navy,
        contentTextStyle: AppTextStyles.body(color: AppColors.white, size: 14),
        actionTextColor: AppColors.gold,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: AppColors.navy),
        titleTextStyle: AppTextStyles.heading(color: AppColors.navy, size: 18),
      ),
      splashFactory: InkRipple.splashFactory,
    );
  }

  /// `builder:` for [showDatePicker] calls. Without this, the calendar
  /// dialog falls back to [light]'s seed-derived `ColorScheme`, which
  /// computes its own `onPrimary`/`onSurface` rather than honoring the
  /// app's hardcoded navy/white pairing — this pins the dialog to the same
  /// explicit navy-on-white convention every other widget in the app uses.
  ///
  /// Every color is set directly on [DatePickerThemeData] rather than left
  /// to infer from a `colorScheme` override — an earlier version of this
  /// only overrode `colorScheme`, which (verified with an actual rendered
  /// golden image, not just reading the framework source) still left the
  /// header's help text/date headline and the entry-mode-toggle icon
  /// rendering in a washed-out blue-grey instead of navy, well under
  /// accessible contrast against the dialog's white background. Explicit
  /// beats inferred: every role a user can actually see text/icons in is
  /// named here, so there's nothing left for a fallback chain to get
  /// wrong.
  ///
  /// The dialog's own text theme is also pinned to the bundled Givonic
  /// font. The month/year toggle ("September 2026"), the OK/Cancel labels
  /// and the text-entry field all draw from [ThemeData.textTheme], which
  /// otherwise has no font family and falls back to Roboto — on web that's
  /// downloaded from fonts.gstatic.com at runtime, and whenever that
  /// download is blocked (e.g. by the site's Content-Security-Policy in
  /// vercel.json) Flutter draws that text with no glyphs at all, i.e.
  /// invisible, while the explicitly-Givonic day numbers still show.
  static Widget datePickerBuilder(BuildContext context, Widget? child) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        textTheme: base.textTheme.apply(
          fontFamily: AppTextStyles.bodyFont,
          fontFamilyFallback: AppTextStyles.fallbackFonts,
          bodyColor: AppColors.navy,
          displayColor: AppColors.navy,
        ),
        colorScheme: const ColorScheme.light(
          primary: AppColors.navy,
          onPrimary: AppColors.white,
          surface: AppColors.white,
          onSurface: AppColors.navy,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: AppColors.white,
          headerBackgroundColor: AppColors.white,
          headerForegroundColor: AppColors.navy,
          headerHeadlineStyle: AppTextStyles.heading(color: AppColors.navy, size: 32),
          headerHelpStyle: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w600),
          weekdayStyle: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w600),
          dayStyle: AppTextStyles.body(color: AppColors.navy, size: 14),
          yearStyle: AppTextStyles.body(color: AppColors.navy, size: 14),
          dayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.white : AppColors.navy,
          ),
          dayBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.navy : null,
          ),
          todayForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.white : AppColors.navy,
          ),
          todayBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.navy : null,
          ),
          todayBorder: const BorderSide(color: AppColors.navy),
          yearForegroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.white : AppColors.navy,
          ),
          yearBackgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.navy : null,
          ),
          cancelButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.navy),
          confirmButtonStyle: TextButton.styleFrom(foregroundColor: AppColors.navy),
        ),
      ),
      child: child!,
    );
  }
}
