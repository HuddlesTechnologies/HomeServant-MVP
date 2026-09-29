import 'package:flutter/material.dart';
import '../core/responsive.dart';
import '../models/user_role.dart';

/// Solid-colour, scrollable page shell shared by every auth / onboarding
/// screen. Flips between navy (tenant) and gold (landlord) via [role].
class ThemedScaffold extends StatelessWidget {
  const ThemedScaffold({
    super.key,
    required this.role,
    required this.child,
    this.showBackButton = true,
  });

  final UserRole role;
  final Widget child;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: role.background,
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: ResponsiveCenter(child: child),
            ),
            if (showBackButton && Navigator.of(context).canPop())
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back_ios_new_rounded, color: role.foreground, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
