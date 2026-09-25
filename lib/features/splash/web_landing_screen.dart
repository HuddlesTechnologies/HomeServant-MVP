import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';

/// The Home Servant marketing site shown at "/" on the web build — a
/// scrolling, multi-section page (hero, About Us, a "what we're building"
/// app teaser, footer) rather than the single-screen splash the native
/// apps use. Swapped in for [kIsWeb] by the router; native platforms keep
/// `SplashScreen`, whose single EXPLORE screen suits an app launch rather
/// than a browser landing page.
class WebLandingScreen extends StatefulWidget {
  const WebLandingScreen({super.key, required this.onGetStarted, required this.onLogin, required this.onGetOnboarded});

  final VoidCallback onGetStarted;
  final VoidCallback onLogin;

  /// "Get Onboarded" — a landlord-specific CTA that skips straight to the
  /// landlord sign-up flow, for landlords who want to list a property before
  /// the app fully launches.
  final VoidCallback onGetOnboarded;

  @override
  State<WebLandingScreen> createState() => _WebLandingScreenState();
}

class _WebLandingScreenState extends State<WebLandingScreen> {
  final _aboutKey = GlobalKey();
  final _buildingKey = GlobalKey();

  void _scrollTo(GlobalKey key) {
    final context = key.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    // White nav bar on both breakpoints — it sits on the navy hero rather
    // than blending into it, so (unlike a navy bar matching a navy hero) it
    // always needs its own separation shadow to read as intentional.
    const navBackground = AppColors.white;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      endDrawer: _MobileNavDrawer(
        onAboutTap: () => _scrollTo(_aboutKey),
        onBuildingTap: () => _scrollTo(_buildingKey),
        onLogin: widget.onLogin,
        onGetStarted: widget.onGetStarted,
        onGetOnboarded: widget.onGetOnboarded,
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 76,
            titleSpacing: 0,
            automaticallyImplyLeading: false,
            // AppBar auto-inserts its own EndDrawerButton here whenever the
            // Scaffold has an endDrawer and `actions` is null OR empty — an
            // empty list still counts as "not provided" (it checks
            // isNotEmpty), so that button showed up as a second hamburger
            // right on top of the one _NavBar draws itself. A throwaway
            // zero-size widget makes the list genuinely non-empty.
            actions: const [SizedBox.shrink()],
            flexibleSpace: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: navBackground,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4))],
              ),
              child: SafeArea(
                bottom: false,
                child: _NavBar(
                  isWide: isWide,
                  onAboutTap: () => _scrollTo(_aboutKey),
                  onBuildingTap: () => _scrollTo(_buildingKey),
                  onLogin: widget.onLogin,
                  onGetStarted: widget.onGetStarted,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _HeroSection(
              isWide: isWide,
              onGetStarted: widget.onGetStarted,
              onLogin: widget.onLogin,
              onScrollCue: () => _scrollTo(_aboutKey),
            ),
          ),
          SliverToBoxAdapter(child: _AboutSection(key: _aboutKey, isWide: isWide)),
          SliverToBoxAdapter(child: _WhatWereBuildingSection(key: _buildingKey, isWide: isWide, onLogin: widget.onLogin)),
          SliverToBoxAdapter(child: _GetOnboardedSection(isWide: isWide, onGetOnboarded: widget.onGetOnboarded)),
          SliverToBoxAdapter(
            child: _Footer(
              onAboutTap: () => _scrollTo(_aboutKey),
              onBuildingTap: () => _scrollTo(_buildingKey),
              onGetOnboarded: widget.onGetOnboarded,
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal max width every section content area is capped at, so text
/// lines don't stretch edge-to-edge on a wide desktop browser.
const double _contentMaxWidth = 1140;

class _Section extends StatelessWidget {
  const _Section({required this.child, required this.isWide, this.verticalPadding});

  final Widget child;
  final bool isWide;
  final double? verticalPadding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 48 : 22,
            vertical: verticalPadding ?? (isWide ? 104 : 64),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One button component for the whole landing page — [PillButton] elsewhere
/// in the app is always full-width (built for stacked form screens), which
/// is the wrong shape for inline marketing CTAs and is why earlier buttons
/// here ended up inconsistent sizes. This one always hugs its label unless
/// [expand] is set, and every call site picks one of two heights.
enum _BtnVariant { primary, outline, dark }

class _LandingButton extends StatelessWidget {
  const _LandingButton({
    required this.label,
    required this.onTap,
    this.variant = _BtnVariant.primary,
    this.dense = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback onTap;
  final _BtnVariant variant;
  final bool dense;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final height = dense ? 38.0 : 52.0;
    final fontSize = dense ? 13.0 : 15.0;
    final horizontalPadding = dense ? 18.0 : 30.0;

    final Color background;
    final Color foreground;
    final BorderSide side;
    switch (variant) {
      case _BtnVariant.primary:
        background = AppColors.gold;
        foreground = AppColors.navy;
        side = BorderSide.none;
      case _BtnVariant.dark:
        background = AppColors.navy;
        foreground = AppColors.white;
        side = BorderSide.none;
      case _BtnVariant.outline:
        background = Colors.white.withValues(alpha: 0.08);
        foreground = AppColors.white;
        side = BorderSide(color: Colors.white.withValues(alpha: 0.35));
    }

    final button = ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        minimumSize: Size(0, height),
        maximumSize: Size(double.infinity, height),
        side: side,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(height / 2)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.button(color: foreground, size: fontSize),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.isWide,
    required this.onAboutTap,
    required this.onBuildingTap,
    required this.onLogin,
    required this.onGetStarted,
  });

  final bool isWide;
  final VoidCallback onAboutTap;
  final VoidCallback onBuildingTap;
  final VoidCallback onLogin;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 48 : 20),
          child: Row(
            children: [
              // logo6.png is the full lockup (mark + wordmark) baked into one
              // graphic — sized by height with its native aspect ratio so the
              // wordmark stays legible instead of being squashed into a square.
              Image.asset('assets/icons/logo6.png', height: isWide ? 34 : 28),
              // The Spacer pushes everything else all the way to the right,
              // keeping the logo pinned to the far left in both layouts.
              const Spacer(),
              if (isWide) ...[
                _NavLink(label: 'About Us', onTap: onAboutTap),
                const SizedBox(width: 28),
                _NavLink(label: 'What We\'re Building', onTap: onBuildingTap),
                const SizedBox(width: 28),
                _NavLink(label: 'Login', onTap: onLogin),
                const SizedBox(width: 22),
                _LandingButton(label: 'Get Started', onTap: onGetStarted, dense: true),
              ] else
                // All nav actions live in the hamburger drawer on mobile —
                // a single icon here instead of a link row + CTA squeezed
                // into a narrow bar.
                IconButton(
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                  color: AppColors.navy,
                  tooltip: 'Menu',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mobile nav's hamburger menu — every action the desktop nav bar
/// offers inline, since the mobile top bar only has room for the logo and
/// the menu icon.
class _MobileNavDrawer extends StatelessWidget {
  const _MobileNavDrawer({
    required this.onAboutTap,
    required this.onBuildingTap,
    required this.onLogin,
    required this.onGetStarted,
    required this.onGetOnboarded,
  });

  final VoidCallback onAboutTap;
  final VoidCallback onBuildingTap;
  final VoidCallback onLogin;
  final VoidCallback onGetStarted;
  final VoidCallback onGetOnboarded;

  void _close(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/icons/logo6.png', height: 30),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: AppColors.navy),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _DrawerLink(label: 'About Us', onTap: () => _close(context, onAboutTap)),
              _DrawerLink(label: 'What We\'re Building', onTap: () => _close(context, onBuildingTap)),
              _DrawerLink(label: 'For Landlords', onTap: () => _close(context, onGetOnboarded)),
              _DrawerLink(label: 'Login', onTap: () => _close(context, onLogin)),
              const Spacer(),
              _LandingButton(label: 'Get Started', onTap: () => _close(context, onGetStarted), expand: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(label, style: AppTextStyles.body(color: AppColors.navy, size: 16, weight: FontWeight.w600)),
      ),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(label, style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.8), size: 14, weight: FontWeight.w600)),
      ),
    );
  }
}


class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.isWide, required this.onGetStarted, required this.onLogin, required this.onScrollCue});

  final bool isWide;
  final VoidCallback onGetStarted;
  final VoidCallback onLogin;
  final VoidCallback onScrollCue;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: isWide ? 780 : 640,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/homepage.jpg', fit: BoxFit.cover),
          DecoratedBox(decoration: BoxDecoration(color: AppColors.navyDark.withValues(alpha: 0.6))),
          Center(
            child: _Section(
              isWide: isWide,
              verticalPadding: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 720 : double.infinity),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: AppTextStyles.heading(color: AppColors.white, size: isWide ? 52 : 32),
                        children: [
                          const TextSpan(text: 'House hunting in Nigeria,\n'),
                          TextSpan(text: 'finally done right.', style: TextStyle(color: AppColors.gold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 480 : double.infinity),
                    child: Text(
                      'Tenants, landlords and vendors, all connected in one place.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.85), size: isWide ? 16 : 14.5),
                    ),
                  ),
                  const SizedBox(height: 36),
                  isWide
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LandingButton(label: 'Get Started', onTap: onGetStarted),
                            const SizedBox(width: 14),
                            _LandingButton(label: 'Log In', onTap: onLogin, variant: _BtnVariant.outline),
                          ],
                        )
                      : Column(
                          children: [
                            _LandingButton(label: 'Get Started', onTap: onGetStarted, expand: true),
                            const SizedBox(height: 12),
                            _LandingButton(label: 'Log In', onTap: onLogin, variant: _BtnVariant.outline, expand: true),
                          ],
                        ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Center(
              child: InkWell(
                onTap: onScrollCue,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.white.withValues(alpha: 0.7), size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({super.key, required this.isWide});

  final bool isWide;

  static const _steps = [
    ('01', 'Browse Verified Listings', 'Houses, shortlets, self-cons and apartments across Nigeria.'),
    ('02', 'Message Landlords Directly', 'Skip the agent. Ask questions and book inspections straight from the app.'),
    ('03', 'Shop the Marketplace', 'Furniture, appliances and fittings from vetted vendors.'),
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.offWhite,
      child: _Section(
        isWide: isWide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ABOUT US', style: AppTextStyles.body(color: AppColors.goldDark, size: 13, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 620 : double.infinity),
              child: Text(
                'Built to help Nigerians find a place they can call home.',
                style: AppTextStyles.heading(color: AppColors.navy, size: isWide ? 34 : 25),
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 620 : double.infinity),
              child: Text(
                'House hunting in Nigeria shouldn’t mean endless calls to agents, unverified listings, or uncertainty about who you’re dealing with. Home Servant changes that. One trusted platform to discover homes, connect with verified people, and move with confidence. And we don’t stop at helping you find a place to live. With our built-in marketplace, you can furnish your new home without starting the search all over again. From finding a home to making it yours, Home Servant keeps everything in one place.',
                style: AppTextStyles.body(color: AppColors.hintGrey, size: 15.5, weight: FontWeight.w400),
              ),
            ),
            SizedBox(height: isWide ? 80 : 52),
            isWide ? _StepsRow(steps: _steps) : _StepsColumn(steps: _steps),
          ],
        ),
      ),
    );
  }
}

class _StepsRow extends StatelessWidget {
  const _StepsRow({required this.steps});

  final List<(String, String, String)> steps;

  @override
  Widget build(BuildContext context) {
    // Generous gutters instead of divider lines between columns — confident
    // whitespace reads more premium than line-art on a minimal brief.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final step in steps) ...[
          Expanded(child: _Step(number: step.$1, title: step.$2, body: step.$3)),
          if (step != steps.last) const SizedBox(width: 56),
        ],
      ],
    );
  }
}

class _StepsColumn extends StatelessWidget {
  const _StepsColumn({required this.steps});

  final List<(String, String, String)> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final step in steps) ...[
          _Step(number: step.$1, title: step.$2, body: step.$3),
          if (step != steps.last) const SizedBox(height: 36),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body});

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(number, style: AppTextStyles.heading(color: AppColors.gold, size: 34)),
        const SizedBox(height: 10),
        Text(title, style: AppTextStyles.body(color: AppColors.navy, size: 16, weight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(body, style: AppTextStyles.body(color: AppColors.hintGrey, size: 13.5)),
      ],
    );
  }
}

class _WhatWereBuildingSection extends StatelessWidget {
  const _WhatWereBuildingSection({super.key, required this.isWide, required this.onLogin});

  final bool isWide;
  final VoidCallback onLogin;

  static const _upcoming = [
    'Verified property listings, updated across every state in Nigeria',
    'Real-time chat with landlords and marketplace vendors',
    'Secure in-app payments, no more cash handovers to strangers',
    'A built-in marketplace for everything you need to move in',
    'One place to track viewings, applications and bookings',
  ];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.navyDark,
      child: _Section(
        isWide: isWide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('COMING SOON', style: AppTextStyles.body(color: AppColors.gold, size: 13, weight: FontWeight.w700)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 780 : double.infinity),
              child: Text(
                'We’re getting ready to launch Home Servant — a smarter, simpler way to find a home in Nigeria.',
                style: AppTextStyles.heading(color: AppColors.white, size: isWide ? 32 : 23),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 640 : double.infinity),
              child: Text(
                'The Home Servant app is in active development, designed to take every frustrating part of finding a home in Nigeria and replace it with one trustworthy, mobile-first experience.',
                style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.75), size: 15),
              ),
            ),
            SizedBox(height: isWide ? 44 : 32),
            isWide
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _UpcomingList(items: _upcoming)),
                        const SizedBox(width: 56),
                        Expanded(child: _CtaCard(onLogin: onLogin)),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      _UpcomingList(items: _upcoming),
                      const SizedBox(height: 28),
                      _CtaCard(onLogin: onLogin),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingList extends StatelessWidget {
  const _UpcomingList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.gold, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(item, style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.88), size: 14.5))),
              ],
            ),
          ),
      ],
    );
  }
}

class _CtaCard extends StatelessWidget {
  const _CtaCard({required this.onLogin});

  final VoidCallback onLogin;

  void _notifyComingSoon(BuildContext context, String platform) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("We'll let you know the moment $platform is ready.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withValues(alpha: 0.14))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Download the Home Servant App', style: AppTextStyles.body(color: AppColors.white, size: 17, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Get first access the moment we launch on Android and iOS.',
            style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.7), size: 13.5),
          ),
          const SizedBox(height: 22),
          _StoreButton(
            icon: Icons.android_rounded,
            eyebrow: 'GET IT ON',
            label: 'Google Play',
            onTap: () => _notifyComingSoon(context, 'Android'),
          ),
          const SizedBox(height: 12),
          _StoreButton(
            icon: Icons.apple_rounded,
            eyebrow: 'Download on the',
            label: 'App Store',
            onTap: () => _notifyComingSoon(context, 'iOS'),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: onLogin,
              child: Text('Or keep using it on the web — Log in', style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.8), size: 13.5, weight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// App-store-badge-style button — used for the (not-yet-published) Android
/// and iOS download links. Taps acknowledge interest rather than opening a
/// real store URL, since neither listing exists yet.
class _StoreButton extends StatelessWidget {
  const _StoreButton({required this.icon, required this.eyebrow, required this.label, required this.onTap});

  final IconData icon;
  final String eyebrow;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.08),
          foregroundColor: AppColors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          minimumSize: const Size(0, 54),
          alignment: Alignment.centerLeft,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.white, size: 26),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(eyebrow, style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.75), size: 10.5)),
                Text(label, style: AppTextStyles.body(color: AppColors.white, size: 15.5, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A landlord-specific CTA — Home Servant hasn't fully launched, but
/// landlords can list a property now and get priority placement once it
/// does. Sits on the warm sand tone (the third of the app's three brand
/// colours) to read as a distinct, dedicated banner rather than another
/// generic content section.
class _GetOnboardedSection extends StatelessWidget {
  const _GetOnboardedSection({required this.isWide, required this.onGetOnboarded});

  final bool isWide;
  final VoidCallback onGetOnboarded;

  @override
  Widget build(BuildContext context) {
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('FOR LANDLORDS', style: AppTextStyles.body(color: AppColors.landlordBrown, size: 13, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        // landlordText — the near-black brown the palette designates for
        // body copy on this exact sand tone (white/navy don't contrast well
        // here); using it is what "every colour, used deliberately" means.
        Text('Get Onboarded Early', style: AppTextStyles.heading(color: AppColors.landlordText, size: isWide ? 32 : 24)),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWide ? 480 : double.infinity),
          child: Text(
            'Home Servant hasn\'t fully launched yet, but you can list your property right now. Landlords who get onboarded early get priority placement the moment we go live.',
            style: AppTextStyles.body(color: AppColors.landlordText.withValues(alpha: 0.75), size: 14.5),
          ),
        ),
      ],
    );

    final cta = _LandingButton(label: 'List Your Property', onTap: onGetOnboarded, variant: _BtnVariant.dark, expand: !isWide);

    return ColoredBox(
      color: AppColors.landlordSand,
      child: _Section(
        isWide: isWide,
        verticalPadding: isWide ? 72 : 56,
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [Expanded(child: copy), const SizedBox(width: 40), cta],
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [copy, const SizedBox(height: 24), cta]),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onAboutTap, required this.onBuildingTap, required this.onGetOnboarded});

  final VoidCallback onAboutTap;
  final VoidCallback onBuildingTap;
  final VoidCallback onGetOnboarded;

  static const _handle = 'homeservantafrica';

  Future<void> _followUs(BuildContext context, String platform) async {
    final uri = switch (platform) {
      'Instagram' => Uri.parse('https://instagram.com/$_handle'),
      'Threads' => Uri.parse('https://www.threads.net/@$_handle'),
      'X' => Uri.parse('https://x.com/$_handle'),
      _ => throw ArgumentError('Unknown platform: $platform'),
    };
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open $platform right now.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    final brand = Column(
      crossAxisAlignment: isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Image.asset('assets/icons/logo7.png', height: 32),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Text(
            'Find Your Perfect House, Just One Click Away.',
            textAlign: isWide ? TextAlign.left : TextAlign.center,
            style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.6), size: 12.5),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SocialIconButton(tooltip: 'Instagram', pathData: _BrandGlyphs.instagram, onTap: () => _followUs(context, 'Instagram')),
            const SizedBox(width: 12),
            _SocialIconButton(tooltip: 'Threads', pathData: _BrandGlyphs.threads, onTap: () => _followUs(context, 'Threads')),
            const SizedBox(width: 12),
            _SocialIconButton(tooltip: 'X', pathData: _BrandGlyphs.x, onTap: () => _followUs(context, 'X')),
          ],
        ),
      ],
    );

    final links = [
      ('About Us', onAboutTap),
      ('What We\'re Building', onBuildingTap),
      ('For Landlords', onGetOnboarded),
    ];

    final linksColumn = Column(
      crossAxisAlignment: isWide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        for (final link in links)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: link.$2,
              child: Text(link.$1, style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.7), size: 13.5, weight: FontWeight.w600)),
            ),
          ),
      ],
    );

    return ColoredBox(
      color: AppColors.navy,
      child: _Section(
        isWide: isWide,
        verticalPadding: isWide ? 56 : 40,
        child: Column(
          children: [
            isWide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Expanded(flex: 3, child: brand), Expanded(flex: 1, child: linksColumn)],
                  )
                : Column(children: [brand, const SizedBox(height: 32), linksColumn]),
            SizedBox(height: isWide ? 40 : 32),
            Divider(color: AppColors.white.withValues(alpha: 0.12), height: 1),
            const SizedBox(height: 24),
            Text(
              '© 2026 Home Servant. All rights reserved.',
              style: AppTextStyles.body(color: AppColors.white.withValues(alpha: 0.45), size: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// A footer social link — opens the real Home Servant account for that
/// platform (handle: homeservantafrica) in an external browser/app.
/// [pathData] is the brand's actual glyph (single-color logo mark) on a
/// 24x24 viewBox, tinted to match the surrounding UI rather than
/// reproduced in brand color.
class _SocialIconButton extends StatelessWidget {
  const _SocialIconButton({required this.tooltip, required this.onTap, required this.pathData});

  final String tooltip;
  final VoidCallback onTap;
  final String pathData;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: SvgPicture.string(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="$pathData"/></svg>',
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(AppColors.white, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

/// Real brand glyph path data (24x24 viewBox), one solid path per mark.
class _BrandGlyphs {
  _BrandGlyphs._();

  static const instagram =
      'M12 0C8.74 0 8.333.014 7.053.072 5.775.132 4.905.333 4.14.63c-.789.306-1.459.717-2.126 1.384S.935 3.35.63 4.14C.333 4.905.131 5.775.072 7.053.014 8.333 0 8.74 0 12s.014 3.667.072 4.947c.06 1.277.261 2.148.558 2.913.306.788.717 1.459 1.384 2.126.667.666 1.336 1.079 2.126 1.384.766.296 1.636.499 2.913.558C8.333 23.986 8.74 24 12 24s3.667-.014 4.947-.072c1.277-.06 2.148-.262 2.913-.558.788-.306 1.459-.718 2.126-1.384.666-.667 1.079-1.335 1.384-2.126.296-.765.499-1.636.558-2.913.058-1.28.072-1.687.072-4.947s-.014-3.667-.072-4.947c-.06-1.277-.262-2.149-.558-2.913-.306-.789-.718-1.459-1.384-2.126C21.319 1.347 20.651.935 19.86.63c-.765-.297-1.636-.499-2.913-.558C15.667.014 15.26 0 12 0zm0 2.16c3.203 0 3.585.016 4.85.071 1.17.055 1.805.249 2.227.415.562.217.96.477 1.382.896.419.42.679.819.896 1.381.164.422.36 1.057.413 2.227.057 1.266.07 1.646.07 4.85s-.015 3.585-.074 4.85c-.061 1.17-.256 1.805-.421 2.227-.224.562-.479.96-.897 1.382-.419.419-.824.679-1.38.896-.42.164-1.065.36-2.235.413-1.274.057-1.649.07-4.859.07-3.211 0-3.586-.015-4.859-.074-1.171-.061-1.816-.256-2.236-.421-.569-.224-.96-.479-1.379-.897-.421-.419-.69-.824-.9-1.38-.165-.42-.359-1.065-.42-2.235-.045-1.26-.061-1.649-.061-4.844 0-3.196.016-3.586.061-4.861.061-1.17.255-1.814.42-2.234.21-.57.479-.96.9-1.381.419-.419.81-.689 1.379-.898.42-.166 1.051-.361 2.221-.421 1.275-.045 1.65-.06 4.859-.06zm0 3.678c-3.405 0-6.162 2.76-6.162 6.162 0 3.405 2.76 6.162 6.162 6.162 3.405 0 6.162-2.76 6.162-6.162 0-3.405-2.76-6.162-6.162-6.162zM12 16c-2.21 0-4-1.79-4-4s1.79-4 4-4 4 1.79 4 4-1.79 4-4 4zm7.846-10.405c0 .795-.646 1.44-1.44 1.44-.795 0-1.44-.645-1.44-1.44 0-.795.645-1.439 1.44-1.439.793-.001 1.44.644 1.44 1.439z';

  static const x =
      'M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z';

  static const threads =
      'M12.186 24h-.007c-3.581-.024-6.334-1.205-8.184-3.509C2.35 18.44 1.5 15.586 1.472 12.01v-.017c.03-3.579.879-6.43 2.525-8.482C5.845 1.205 8.6.024 12.18 0h.014c2.746.02 5.043.725 6.826 2.098 1.677 1.29 2.858 3.13 3.509 5.467l-2.04.569c-1.104-3.96-3.898-5.984-8.304-6.015-2.91.022-5.11.936-6.54 2.717C4.307 6.504 3.616 8.914 3.589 12c.027 3.086.718 5.496 2.057 7.164 1.43 1.781 3.63 2.695 6.54 2.717 2.623-.02 4.358-.631 5.8-2.045 1.647-1.613 1.618-3.593 1.09-4.798-.31-.71-.873-1.3-1.634-1.75-.192 1.352-.622 2.446-1.284 3.272-.886 1.102-2.14 1.704-3.73 1.79-1.202.065-2.361-.218-3.259-.801-1.063-.689-1.685-1.74-1.752-2.964-.065-1.19.408-2.285 1.33-3.082.88-.76 2.119-1.207 3.583-1.291a13.853 13.853 0 0 1 3.02.142c-.126-.75-.404-1.348-.83-1.78-.585-.594-1.489-.897-2.685-.897h-.03c-1.09.007-2.475.31-3.377 1.673l-1.784-1.226c1.126-1.71 2.887-2.652 4.988-2.664h.045c3.19 0 5.28 1.951 5.481 5.146.116.058.229.117.34.178 1.573.86 2.726 2.146 3.259 3.617.749 2.043.771 5.318-1.941 7.99-1.848 1.82-4.056 2.62-7.03 2.65Zm2.02-11.777c-.169-.01-.34-.017-.516-.017-.14 0-.28.005-.42.013-1.783.098-2.89.878-2.827 2.03.065 1.19.943 1.878 2.482 1.878.05 0 .098 0 .148-.002 1.05-.02 1.877-.375 2.395-1.026.398-.5.66-1.198.777-2.088-.618-.288-1.303-.443-2.039-.788Z';
}
