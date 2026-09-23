import 'package:flutter/material.dart';
import '../../../models/dashboard_theme.dart';
import '../../../widgets/dashboard_tab_scaffold.dart';
import '../../../widgets/floating_pill_nav.dart';

/// Floating pill nav for the vendor dashboard — same [FloatingPillNav]
/// shape as the tenant/landlord bars, with a vendor-specific icon set
/// (Overview / Products / Profile instead of Home / Marketplace / Docs /
/// Profile).
class VendorBottomNav extends StatelessWidget {
  const VendorBottomNav({super.key, required this.currentIndex, required this.onTap, required this.theme});

  final int currentIndex;
  final ValueChanged<int> onTap;
  final DashboardTheme theme;

  static const _icons = [Icons.dashboard_rounded, Icons.inventory_2_outlined, Icons.storefront_rounded];

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

/// Shared page shell for the 3 vendor screens (Overview / Products /
/// Profile) — floats [VendorBottomNav] over [body] the same way on all
/// three, without any of them needing to import one another just to host
/// the nav bar. Built on the cross-dashboard [DashboardTabScaffold].
class VendorTabScaffold extends StatelessWidget {
  const VendorTabScaffold({
    super.key,
    required this.theme,
    required this.currentIndex,
    required this.onNavTap,
    required this.body,
  });

  final DashboardTheme theme;
  final int currentIndex;
  final ValueChanged<int> onNavTap;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return DashboardTabScaffold(
      background: theme.background,
      navBar: VendorBottomNav(currentIndex: currentIndex, onTap: onNavTap, theme: theme),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: body)),
    );
  }
}
