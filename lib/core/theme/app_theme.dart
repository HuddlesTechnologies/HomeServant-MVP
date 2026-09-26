import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navy,
        primary: AppColors.navy,
        secondary: AppColors.gold,
      ),
      textTheme: TextTheme(
        bodyMedium: AppTextStyles.body(color: AppColors.navy),
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
  static Widget datePickerBuilder(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: AppColors.navy,
          onPrimary: AppColors.white,
          surface: AppColors.white,
          onSurface: AppColors.navy,
        ),
      ),
      child: child!,
    );
  }
}
