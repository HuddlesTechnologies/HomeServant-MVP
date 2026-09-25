import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/vendor.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/upload_picker.dart';
import 'vendor_bank_details_screen.dart';

/// Lets the vendor update their shop's public details, logo, and payout
/// bank account.
class VendorEditProfileScreen extends StatefulWidget {
  const VendorEditProfileScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorEditProfileScreen> createState() => _VendorEditProfileScreenState();
}

class _VendorEditProfileScreenState extends State<VendorEditProfileScreen> {
  final _businessName = TextEditingController();
  final _ownerName = TextEditingController();
  MarketplaceCategory _category = MarketplaceCategory.other;
  String? _logoUrl;
  PickedUpload? _newLogo;
  VendorProfile? _vendor;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    try {
      final vendor = await appState.vendors.me();
      if (!mounted) return;
      setState(() {
        _vendor = vendor;
        _businessName.text = vendor.businessName;
        _ownerName.text = appState.fullName;
        _category = vendor.category;
        _logoUrl = vendor.logoUrl;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _businessName.dispose();
    _ownerName.dispose();
    super.dispose();
  }

  Future<void> _openBankDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VendorBankDetailsScreen(theme: widget.theme)),
    );
    _load();
  }

  Future<void> _pickLogo() async {
    final picked = await pickUpload(context);
    if (picked != null && picked.isImage) {
      setState(() {
        _newLogo = picked;
        _logoUrl = null;
      });
    }
  }

  Future<void> _pickCategory() async {
    final theme = widget.theme;
    final result = await showModalBottomSheet<MarketplaceCategory>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final option in MarketplaceCategory.values)
              ListTile(
                title: Text(option.label, style: AppTextStyles.body(color: theme.onSurface)),
                trailing: option == _category ? Icon(Icons.check, color: theme.accent) : null,
                onTap: () => Navigator.pop(context, option),
              ),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _category = result);
  }

  Future<void> _save() async {
    final newName = _businessName.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Business name cannot be empty')));
      return;
    }
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      var logoUrl = _logoUrl;
      final newLogo = _newLogo;
      if (newLogo != null) {
        logoUrl = await appState.uploads.upload(file: newLogo, folder: 'vendor-logos');
      }
      await appState.vendors.update(
        businessName: newName,
        category: _category,
        logoUrl: logoUrl,
      );
      final newOwnerName = _ownerName.text.trim();
      if (newOwnerName.isNotEmpty && newOwnerName != appState.fullName) {
        await appState.completeProfile(fullName: newOwnerName);
      }
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Shop profile updated')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    if (_loading || _vendor == null) {
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          backgroundColor: theme.background,
          elevation: 0,
          iconTheme: IconThemeData(color: theme.foreground),
          title: Text('Edit Shop Profile', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Edit Shop Profile', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickLogo,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: theme.accent.withValues(alpha: 0.15),
                        backgroundImage: _newLogo != null
                            ? _newLogo!.imageProvider
                            : (_logoUrl != null ? imageProviderForPath(_logoUrl!) : null),
                        child: _newLogo == null && _logoUrl == null
                            ? Icon(Icons.storefront_rounded, color: theme.accent, size: 38)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: theme.background, width: 2),
                          ),
                          child: Icon(Icons.camera_alt_rounded, size: 16, color: theme.onAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _pickLogo,
                  child: Text('Change Logo', style: AppTextStyles.body(color: theme.accent, weight: FontWeight.w700, size: 13)),
                ),
              ),
              const SizedBox(height: 20),
              _Field(theme: theme, label: 'Business Name', controller: _businessName, hint: 'e.g. Comfort Home Furniture'),
              const SizedBox(height: 16),
              _Field(theme: theme, label: "Owner's Full Name", controller: _ownerName, hint: 'Full name'),
              const SizedBox(height: 16),
              _Dropdown(theme: theme, label: 'Business Category', value: _category.label, onTap: _pickCategory),
              const SizedBox(height: 28),
              Text('Payout Account', style: AppTextStyles.heading(color: theme.foreground, size: 16)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Payouts are sent to this account only after an order has been verified and marked '
                  'completed — not immediately at purchase.',
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.75), size: 12.5),
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _openBankDetails,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_rounded, color: theme.accent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _vendor!.hasPayoutDetails ? 'Bank Details' : 'Set Up Bank Details',
                              style: AppTextStyles.body(color: theme.onSurface, weight: FontWeight.w700, size: 14),
                            ),
                            if (_vendor!.hasPayoutDetails)
                              Text(
                                '${_vendor!.bankName ?? 'Bank'} · ${_vendor!.accountName ?? _vendor!.accountNumber}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12),
                              )
                            else
                              Text(
                                'Required before you can list a product',
                                style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              PillButton(
                label: _saving ? 'Saving…' : 'Save Changes',
                backgroundColor: theme.accent,
                textColor: theme.onAccent,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.theme, required this.label, required this.controller, this.keyboardType, this.hint = ''});

  final DashboardTheme theme;
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body(color: theme.foreground, weight: FontWeight.w600, size: 13.5)),
        const SizedBox(height: 8),
        PillTextField(
          hint: hint,
          controller: controller,
          keyboardType: keyboardType,
          fillColor: theme.surface,
          textColor: theme.onSurface,
        ),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.theme, required this.label, required this.value, required this.onTap});

  final DashboardTheme theme;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body(color: theme.foreground, weight: FontWeight.w600, size: 13.5)),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(28)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(value, style: AppTextStyles.body(color: theme.onSurface, size: 15)),
                Icon(Icons.keyboard_arrow_down_rounded, color: theme.onSurface.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
