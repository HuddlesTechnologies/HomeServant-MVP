import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// Shared 4-digit PIN dot indicator + numeric keypad used by the app-lock
/// setup, verification, and unlock-gate screens.
class PinDots extends StatelessWidget {
  const PinDots({super.key, required this.length, required this.filled, this.color = AppColors.navy});

  final int length;
  final int filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final isFilled = i < filled;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? color : Colors.transparent,
            border: Border.all(color: color, width: 1.4),
          ),
        );
      }),
    );
  }
}

class PinKeypad extends StatelessWidget {
  const PinKeypad({super.key, required this.onDigit, required this.onBackspace, this.color = AppColors.navy});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', 'back'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      childAspectRatio: 1.7,
      children:
          keys.map((key) {
            if (key.isEmpty) return const SizedBox.shrink();
            if (key == 'back') {
              return IconButton(tooltip: 'Delete digit', onPressed: onBackspace, icon: Icon(Icons.backspace_outlined, color: color));
            }
            return InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: () => onDigit(key),
              child: Center(child: Text(key, style: AppTextStyles.heading(color: color, size: 24))),
            );
          }).toList(),
    );
  }
}
