import 'package:flutter/material.dart';
import '../core/theme/app_text_styles.dart';

/// Fully-rounded call-to-action button used for "Login" / "Continue" /
/// "Explore" throughout the prototype.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.textColor,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color textColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: textColor),
              )
            : Text(label, style: AppTextStyles.button(color: textColor)),
      ),
    );
  }
}

/// Secondary, outlined pill used for the "Certificate of Ownership" upload
/// action and similar white-on-white affordances.
class PillOutlineButton extends StatelessWidget {
  const PillOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.textColor,
    this.backgroundColor = Colors.white,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color textColor;
  final Color backgroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: textColor, size: 18),
              const SizedBox(width: 8),
            ],
            Text(label, style: AppTextStyles.button(color: textColor, size: 15)),
          ],
        ),
      ),
    );
  }
}
