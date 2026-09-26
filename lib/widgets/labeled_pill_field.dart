import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'pill_text_field.dart';

/// Label-above-textfield wrapper used across the onboarding/signup forms
/// (landlord/tenant profile steps, vendor signup) — promoted from the
/// near-identical private `_Field` widgets those screens used to each
/// define on their own.
class LabeledPillField extends StatelessWidget {
  const LabeledPillField({
    super.key,
    required this.label,
    required this.labelColor,
    required this.controller,
    this.keyboardType,
    this.hint = '',
    this.readOnly = false,
    this.onTap,
    this.trailing,
    this.obscureText = false,
    this.minLines,
    this.maxLines = 1,
    this.labelSize = 15,
    this.fillColor = AppColors.white,
    this.textColor = AppColors.navy,
    this.validator,
  });

  final String label;
  final Color labelColor;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String hint;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool obscureText;
  final int? minLines;
  final int? maxLines;
  final double labelSize;
  final Color fillColor;
  final Color textColor;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body(color: labelColor, weight: FontWeight.w600, size: labelSize),
        ),
        const SizedBox(height: 8),
        PillTextField(
          hint: hint,
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          trailing: trailing,
          obscureText: obscureText,
          minLines: minLines,
          maxLines: obscureText ? 1 : maxLines,
          fillColor: fillColor,
          textColor: textColor,
          validator: validator,
        ),
      ],
    );
  }
}
