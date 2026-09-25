import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import 'marketplace_home_screen.dart';
import 'vendor_dashboard_screen.dart';
import 'vendor_signup_screen.dart';

/// Entry point for the Marketplace tab (the dashboard's cart icon). Asks
/// whether the visitor wants to shop as a customer or sell as a vendor
/// before handing off to the matching flow. The vendor side needs no
/// separate login — it's the same account (see AppState.hasVendorProfile) —
/// so this just branches on whether a shop already exists.
class MarketplaceAuthScreen extends StatefulWidget {
  const MarketplaceAuthScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<MarketplaceAuthScreen> createState() => _MarketplaceAuthScreenState();
}

class _MarketplaceAuthScreenState extends State<MarketplaceAuthScreen> {
  bool? _hasVendorProfile;

  @override
  void initState() {
    super.initState();
    _checkVendorProfile();
  }

  Future<void> _checkVendorProfile() async {
    final appState = context.read<AppState>();
    final existing = appState.hasVendorProfile;
    final hasProfile = existing ?? await appState.checkVendorProfile();
    if (!mounted) return;
    setState(() => _hasVendorProfile = hasProfile);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final hasVendorProfile = _hasVendorProfile ?? false;
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ResponsiveCenter(
                child: Column(
                  children: [
                    const SizedBox(height: 60),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(color: theme.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Icon(Icons.storefront_rounded, color: theme.accent, size: 40),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Home Servant Marketplace',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.heading(color: theme.foreground, size: 24),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Furniture, appliances, fittings and more — everything you need to move in, in one place.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.65), size: 15),
                    ),
                    const SizedBox(height: 48),
                    PillButton(
                      label: 'Proceed as a Customer',
                      backgroundColor: theme.accent,
                      textColor: theme.onAccent,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => MarketplaceHomeScreen(theme: theme)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    PillOutlineButton(
                      label: hasVendorProfile ? 'Go to My Shop' : 'Become a Vendor',
                      backgroundColor: theme.surface,
                      textColor: theme.onSurface,
                      icon: Icons.storefront_outlined,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => hasVendorProfile
                              ? VendorDashboardScreen(theme: theme)
                              : VendorSignupScreen(theme: theme),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 8,
              child: IconButton(
                onPressed: () => context.pop(),
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: theme.foreground, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
