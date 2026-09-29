import 'package:flutter/material.dart';
import '../../../models/dashboard_theme.dart';
import '../vendor_dashboard_screen.dart';
import '../vendor_products_screen.dart';
import '../vendor_profile_screen.dart';

/// Maps a [VendorBottomNav] tab index to its screen — Overview / Products /
/// Profile, in that order — so the three vendor tab screens share one
/// definition of which screen lives at which index instead of each
/// duplicating its own index→screen switch.
Widget vendorTabRoute(int index, DashboardTheme theme) => switch (index) {
  0 => VendorDashboardScreen(theme: theme),
  1 => VendorProductsScreen(theme: theme),
  _ => VendorProfileScreen(theme: theme),
};
