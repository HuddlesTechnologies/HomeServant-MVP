import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/vendor.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/profile_edit_button.dart';
import '../../widgets/support_sheet.dart';
import '../../widgets/upload_picker.dart';
import 'marketplace_auth_screen.dart';
import 'vendor_edit_profile_screen.dart';
import 'vendor_transactions_screen.dart';
import 'widgets/vendor_bottom_nav.dart';
import 'widgets/vendor_tab_route.dart';

/// The vendor's own shop profile — business details plus the "Danger
/// Zone" actions (deactivating the shop). Reached from the vendor
/// dashboard's bottom nav.
class VendorProfileScreen extends StatefulWidget {
  const VendorProfileScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorProfileScreen> createState() => _VendorProfileScreenState();
}

class _VendorProfileScreenState extends State<VendorProfileScreen> {
  DashboardTheme get theme => widget.theme;
  VendorProfile? _vendor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final vendor = await context.read<AppState>().vendors.me();
      if (!mounted) return;
      setState(() => _vendor = vendor);
    } catch (_) {
      // Handled by the loading state staying null; the screen just shows a spinner.
    }
  }

  void _onNavTap(BuildContext context, int index) {
    if (index == 2) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => vendorTabRoute(index, theme)));
  }

  Future<void> _editProfile(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VendorEditProfileScreen(theme: theme)),
    );
    _load();
  }

  /// "Vendor mode" is the *same* account/session as everywhere else in the
  /// app (see AppState.hasVendorProfile) — there's no separate vendor
  /// login to sign out of. So this doesn't end the session at all; it
  /// resets the Marketplace's own nested navigation stack back to
  /// MarketplaceAuthScreen, the "Proceed as a Customer" / "Go to My Shop"
  /// choice screen — letting a tenant who's also a vendor step back into
  /// shopping as a customer without losing their account session (which a
  /// real sign-out would, since re-login would just route them straight
  /// back into vendor mode via MarketplaceNavigatorHost's own
  /// hasVendorProfile check). Ending the whole account session is still
  /// available via "Go to Tenant Dashboard" below, then that dashboard's
  /// own Log Out.
  void _exitVendorMode(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MarketplaceAuthScreen(theme: theme)),
      (route) => false,
    );
  }

  Future<void> _confirmDeactivate(BuildContext context) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _ConfirmSheet(
        theme: theme,
        title: 'Deactivate your shop?',
        body:
            "Your products will be taken off the marketplace and customers won't be able to reach you. "
            'You can become a vendor again any time.',
        actionLabel: 'Deactivate',
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<AppState>().vendors.update(isActive: false);
      messenger.showSnackBar(const SnackBar(content: Text('Your shop has been deactivated')));
      navigator.popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = _vendor;
    if (vendor == null) {
      return VendorTabScaffold(
        theme: theme,
        currentIndex: 2,
        onNavTap: (index) => _onNavTap(context, index),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final appState = context.watch<AppState>();
    return VendorTabScaffold(
      theme: theme,
      currentIndex: 2,
      onNavTap: (index) => _onNavTap(context, index),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shop Profile', style: AppTextStyles.heading(color: theme.foreground, size: 20)),
              ProfileEditButton(color: theme.accent, compact: true, onTap: () => _editProfile(context)),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: theme.accent.withValues(alpha: 0.15),
                  backgroundImage: vendor.logoUrl != null ? imageProviderForPath(vendor.logoUrl!) : null,
                  child: vendor.logoUrl == null ? Icon(Icons.storefront_rounded, color: theme.accent, size: 36) : null,
                ),
                const SizedBox(height: 12),
                Text(vendor.businessName, style: AppTextStyles.heading(color: theme.foreground, size: 18)),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                _ProfileRow(theme: theme, label: 'Owner', value: appState.fullName.isEmpty ? '—' : appState.fullName),
                _ProfileRow(theme: theme, label: 'Email', value: appState.email),
                _ProfileRow(theme: theme, label: 'Category', value: vendor.category.label),
                _ProfileRow(theme: theme, label: 'State', value: vendor.state, showDivider: false),
              ],
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => VendorTransactionsScreen(theme: theme)),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_outlined, color: theme.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Transaction History',
                      style: AppTextStyles.body(color: theme.onSurface, weight: FontWeight.w700, size: 14),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => showSupportOptionsSheet(context, theme: theme),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(Icons.support_agent_rounded, color: theme.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Contact Support',
                      style: AppTextStyles.body(color: theme.onSurface, weight: FontWeight.w700, size: 14),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => context.go('/dashboard'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, color: theme.accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Go to Tenant Dashboard',
                      style: AppTextStyles.body(color: theme.onSurface, weight: FontWeight.w700, size: 14),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _exitVendorMode(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: theme.onSurface, size: 18),
                  const SizedBox(width: 8),
                  Text('Exit Vendor Mode', style: AppTextStyles.body(color: theme.onSurface, weight: FontWeight.w700, size: 14)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'DANGER ZONE',
              style: AppTextStyles.body(color: Colors.redAccent, size: 12, weight: FontWeight.w700).copyWith(letterSpacing: 0.6),
            ),
          ),
          GestureDetector(
            onTap: () => _confirmDeactivate(context),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  const Icon(Icons.pause_circle_outline_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Deactivate Shop',
                      style: AppTextStyles.body(color: Colors.redAccent, weight: FontWeight.w700, size: 14),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.theme, required this.label, required this.value, this.showDivider = true});

  final DashboardTheme theme;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 13)),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: theme.onSurface, size: 13.5, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) Divider(color: theme.onSurface.withValues(alpha: 0.1), height: 1),
      ],
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.theme, required this.title, required this.body, required this.actionLabel});

  final DashboardTheme theme;
  final String title;
  final String body;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.heading(color: theme.onSurface, size: 19)),
            const SizedBox(height: 8),
            Text(body, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 14)),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: theme.onSurface),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text('Cancel', style: AppTextStyles.button(color: theme.onSurface, size: 14)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Text(actionLabel, style: AppTextStyles.button(color: Colors.white, size: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
