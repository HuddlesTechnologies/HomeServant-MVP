import 'package:flutter/material.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/dashboard_theme.dart';
import '../../../widgets/labeled_pill_field.dart';

/// A labelled text field in the vendor forms (Become a Vendor, Edit Shop):
/// [DashboardTheme.foreground] label on the page background, and
/// [DashboardTheme.onSurface] text on a [DashboardTheme.surface] fill.
/// Both vendor screens used to carry their own private copy.
class VendorTextField extends StatelessWidget {
  const VendorTextField({
    super.key,
    required this.label,
    required this.theme,
    required this.controller,
    this.keyboardType,
    this.hint = '',
  });

  final String label;
  final DashboardTheme theme;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return LabeledPillField(
      label: label,
      labelColor: theme.foreground,
      labelSize: 13.5,
      controller: controller,
      keyboardType: keyboardType,
      hint: hint,
      fillColor: theme.surface,
      textColor: theme.onSurface,
    );
  }
}

/// The dropdown counterpart of [VendorTextField] (same color pairs), which
/// opens a picker via [onTap].
class VendorDropdownField extends StatelessWidget {
  const VendorDropdownField({
    super.key,
    required this.label,
    required this.theme,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DashboardTheme theme;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body(color: theme.foreground, weight: FontWeight.w600, size: 13.5)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(28)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(value, style: AppTextStyles.body(color: theme.onSurface, size: 15)),
                Icon(Icons.keyboard_arrow_down_rounded, color: theme.onSurface.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
