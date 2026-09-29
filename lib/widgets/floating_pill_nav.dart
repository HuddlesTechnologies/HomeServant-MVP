import 'package:flutter/material.dart';

/// The floating, rounded-pill bottom nav bar shape shared by every
/// dashboard (tenant, landlord, vendor): a row of icons over a coloured
/// pill, where the selected icon gets its own filled circle behind it.
/// Each dashboard's nav bar is a thin wrapper that supplies [itemCount],
/// [iconBuilder] and its colours.
class FloatingPillNav extends StatelessWidget {
  const FloatingPillNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.itemCount,
    required this.labels,
    required this.iconBuilder,
    required this.backgroundColor,
    required this.selectedBackgroundColor,
    required this.selectedColor,
    required this.unselectedColor,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int itemCount;

  /// What each icon is called ("Home", "Messages"...). Read out by screen
  /// readers and shown as a tooltip on hover — without it an icon-only nav
  /// is announced as just "button".
  final List<String> labels;

  /// Builds the icon for [index], already tinted the right colour for its
  /// selected/unselected state.
  final Widget Function(int index, Color color) iconBuilder;

  final Color backgroundColor;
  final Color selectedBackgroundColor;
  final Color selectedColor;
  final Color unselectedColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(itemCount, (index) {
          final selected = index == currentIndex;
          return Tooltip(
            message: labels[index],
            child: Semantics(
              button: true,
              selected: selected,
              child: GestureDetector(
                onTap: () => onTap(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected ? selectedBackgroundColor : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: iconBuilder(index, selected ? selectedColor : unselectedColor),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
