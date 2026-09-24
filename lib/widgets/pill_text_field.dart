import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// White, fully-rounded input used throughout every auth / onboarding
/// screen in the prototype. When [obscureText] is true and the caller
/// hasn't supplied its own [trailing] widget, shows a built-in
/// show/hide-password toggle instead of leaving the field permanently
/// masked with no way to check what was typed.
class PillTextField extends StatefulWidget {
  const PillTextField({
    super.key,
    required this.hint,
    this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.fillColor = AppColors.white,
    this.textColor = AppColors.navy,
    this.trailing,
    this.onTap,
    this.readOnly = false,
    this.validator,
    this.inputFormatters,
    this.minLines,
    this.maxLines = 1,
    this.borderRadius = 28,
    this.focusNode,
  });

  final String hint;
  final TextEditingController? controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Color fillColor;
  final Color textColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool readOnly;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int? maxLines;
  final double borderRadius;
  final FocusNode? focusNode;

  @override
  State<PillTextField> createState() => _PillTextFieldState();
}

class _PillTextFieldState extends State<PillTextField> {
  late bool _obscured = widget.obscureText;

  @override
  void didUpdateWidget(covariant PillTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A caller driving visibility externally (its own IconButton passed as
    // `trailing`, e.g. AdminLoginScreen) toggles its own state and passes
    // a new `obscureText` down — without this, `_obscured` stayed frozen
    // at whatever it was on first build, so the field never actually
    // revealed the password despite the icon itself flipping.
    if (oldWidget.obscureText != widget.obscureText) {
      _obscured = widget.obscureText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final showPasswordToggle = widget.obscureText && widget.trailing == null;
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscured,
      keyboardType: widget.keyboardType,
      onTap: widget.onTap,
      readOnly: widget.readOnly,
      validator: widget.validator,
      inputFormatters: widget.inputFormatters,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      style: AppTextStyles.body(color: widget.textColor, size: 16),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 16),
        filled: true,
        fillColor: widget.fillColor,
        suffixIcon: showPasswordToggle
            ? IconButton(
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: widget.textColor.withValues(alpha: 0.6),
                ),
              )
            : widget.trailing,
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
      ),
    );
  }
}

/// A field styled to look tappable (dropdown / picker) with a label above
/// it and a chevron, matching "Upload your Address" / "Means of
/// Identification" on the second onboarding step.
class LabeledDropdownField extends StatelessWidget {
  const LabeledDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.labelColor,
    this.fillColor = AppColors.white,
    this.onTap,
  });

  final String label;
  final String value;
  final Color labelColor;
  final Color fillColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.body(color: labelColor, weight: FontWeight.w600)),
            Icon(Icons.keyboard_arrow_down_rounded, color: labelColor),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 15)),
          ),
        ),
      ],
    );
  }
}
