import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/floating_pill_nav.dart';
import 'landlord_widgets.dart';

/// Floating pill nav for the redesigned landlord dashboard — same
/// [FloatingPillNav] shape as the tenant/vendor bars, but with its own
/// fixed navy/gold palette and icon set (Home / Messages / Bookings /
/// Profile) that matches the new landlord mockups pixel-for-pixel, rather
/// than remapping onto the tenant-facing [DashboardTheme] palettes.
class LandlordBottomNav extends StatelessWidget {
  const LandlordBottomNav({super.key, required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return FloatingPillNav(
      currentIndex: currentIndex,
      onTap: onTap,
      itemCount: 4,
      backgroundColor: AppColors.navy,
      selectedBackgroundColor: AppColors.gold,
      selectedColor: AppColors.navy,
      unselectedColor: AppColors.sand.withValues(alpha: 0.8),
      iconBuilder: _iconFor,
    );
  }

  static Widget _iconFor(int index, Color color) {
    switch (index) {
      case 0:
        return Icon(Icons.home_rounded, color: color, size: 22);
      case 1:
        return Icon(Icons.mail_outline_rounded, color: color, size: 22);
      case 2:
        return HouseBookingIcon(color: color, size: 22);
      default:
        return Icon(Icons.person_outline_rounded, color: color, size: 22);
    }
  }
}
