import 'package:flutter/material.dart';
import '../core/theme/app_text_styles.dart';

/// A validation message under a field. Always present in the widget tree
/// (empty when [message] is null): inserting it only on error shifted every
/// later sibling, so Flutter rebuilt the form fields below it and threw
/// away their own error text.
class FieldErrorText extends StatelessWidget {
  const FieldErrorText(this.message, {super.key, required this.color, this.textAlign});

  final String? message;
  final Color color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, textAlign: textAlign, style: AppTextStyles.body(color: color, size: 12.5)),
    );
  }
}
