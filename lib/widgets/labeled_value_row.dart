import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// A read-only "label: value" row — grey label in a fixed-width column,
/// navy value beside it. For the light (white/off-white) detail cards on
/// the admin screens and the landlord's view of a tenant's profile, which
/// used to each carry their own copy of this widget.
class LabeledValueRow extends StatelessWidget {
  const LabeledValueRow(this.label, this.value, {super.key, this.labelWidth = 140, this.verticalPadding = 6});

  final String label;
  final String value;
  final double labelWidth;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
