import 'package:flutter/material.dart';
import '../../../models/dashboard_theme.dart';
import '../../../widgets/floating_pill_nav.dart';

class DashboardBottomNav extends StatelessWidget {
  const DashboardBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.theme,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final DashboardTheme theme;

  static const _icons = [
    Icons.home_rounded,
    Icons.shopping_cart_outlined,
    Icons.description_outlined,
    Icons.person_outline_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return FloatingPillNav(
      currentIndex: currentIndex,
      onTap: onTap,
      itemCount: _icons.length,
      backgroundColor: theme.navigatorColor,
      selectedBackgroundColor: theme.background,
      selectedColor: theme.accent,
      unselectedColor: theme.navigatorForeground,
      iconBuilder: (index, color) => Icon(_icons[index], color: color, size: 22),
    );
  }
}
