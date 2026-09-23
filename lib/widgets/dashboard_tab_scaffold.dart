import 'package:flutter/material.dart';

/// Shared page shell for every tabbed dashboard (tenant, landlord, vendor):
/// a [Scaffold] with [navBar] floated over the bottom-centre. Each
/// dashboard used to duplicate this exact `Scaffold` > `SafeArea` > `Stack`
/// > `Positioned` structure with only the body, nav bar, and background
/// colour differing.
///
/// [body] is placed as-is — dashboards vary in whether (and how wide) they
/// self-constrain their own content (e.g. the tenant feed cheats its
/// desktop width wider than the landlord/vendor ones), so that stays the
/// caller's job rather than being forced uniform here.
class DashboardTabScaffold extends StatelessWidget {
  const DashboardTabScaffold({
    super.key,
    required this.background,
    required this.navBar,
    required this.body,
    this.navBarMaxWidth = 420,
  });

  final Color background;
  final Widget navBar;
  final Widget body;

  /// Caps how wide [navBar] stretches on desktop/tablet browsers, so the
  /// pill nav doesn't sprawl edge-to-edge on wide viewports.
  final double navBarMaxWidth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Stack(
          children: [
            body,
            Positioned(
              left: 20,
              right: 20,
              bottom: 12,
              child: Center(
                child: ConstrainedBox(constraints: BoxConstraints(maxWidth: navBarMaxWidth), child: navBar),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
