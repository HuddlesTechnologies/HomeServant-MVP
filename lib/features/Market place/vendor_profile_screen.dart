import 'package:flutter/material.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../widgets/profile_edit_button.dart';
import '../../widgets/support_sheet.dart';
import '../../widgets/upload_picker.dart';
import 'models/vendor.dart';
import 'vendor_dashboard_screen.dart';
import 'vendor_edit_profile_screen.dart';
import 'vendor_products_screen.dart';
import 'vendor_transactions_screen.dart';
import 'widgets/vendor_bottom_nav.dart';

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

  void _onNavTap(BuildContext context, int index) {
    if (index == 2) return;
    final screen = index == 0 ? VendorDashboardScreen(theme: theme) : VendorProductsScreen(theme: theme);
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _editProfile(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VendorEditProfileScreen(theme: theme)),
    );
    setState(() {});
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
    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your shop has been deactivated')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = mockLoggedInVendor;
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
                  backgroundImage: vendor.logoPath != null ? imageProviderForPath(vendor.logoPath!) : null,
                  child: vendor.logoPath == null ? Icon(Icons.storefront_rounded, color: theme.accent, size: 36) : null,
                ),
                const SizedBox(height: 12),
                Text(vendor.businessName, style: AppTextStyles.heading(color: theme.foreground, size: 18)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: Colors.amber.shade600, size: 16),
                    const SizedBox(width: 2),
                    Text('${vendor.rating}', style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.7), size: 13)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                _ProfileRow(theme: theme, label: 'Owner', value: vendor.ownerName),
                _ProfileRow(theme: theme, label: 'Email', value: vendor.email),
                _ProfileRow(theme: theme, label: 'Category', value: vendor.category),
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
            onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: theme.onSurface, size: 18),
                  const SizedBox(width: 8),
                  Text('Log Out', style: AppTextStyles.body(color: theme.onSurface, weight: FontWeight.w700, size: 14)),
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
