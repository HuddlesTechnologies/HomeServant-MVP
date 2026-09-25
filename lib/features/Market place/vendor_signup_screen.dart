import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/vendor.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/labeled_pill_field.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/upload_picker.dart';
import '../dashboard/models/property.dart';
import 'vendor_dashboard_screen.dart';

/// Shop-setup form for an already-authenticated tenant/vendor (see
/// AppState.hasVendorProfile) — the same login can shop as a customer and
/// sell as a vendor, so this is just `POST /vendors/me`'s business-profile
/// fields, not a separate account/password/OTP signup.
class VendorSignupScreen extends StatefulWidget {
  const VendorSignupScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorSignupScreen> createState() => _VendorSignupScreenState();
}

class _VendorSignupScreenState extends State<VendorSignupScreen> {
  final _businessName = TextEditingController();
  final _rcNumber = TextEditingController();

  MarketplaceCategory? _category;
  String? _state;
  PickedUpload? _logo;
  bool _submitting = false;

  @override
  void dispose() {
    _businessName.dispose();
    _rcNumber.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picked = await pickUpload(context);
    if (picked != null) setState(() => _logo = picked);
  }

  Future<void> _pickCategory() async {
    final result = await _showPicker(
      title: 'Business Category',
      options: marketplaceCategoryLabels,
      current: _category?.label,
    );
    if (result != null) {
      setState(() => _category = MarketplaceCategoryApi.fromLabel(result));
    }
  }

  Future<void> _pickState() async {
    final result = await _showPicker(
      title: 'State',
      options: nigerianStates,
      current: _state,
    );
    if (result != null) setState(() => _state = result);
  }

  Future<String?> _showPicker({
    required String title,
    required List<String> options,
    String? current,
  }) {
    final theme = widget.theme;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (context) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: AppTextStyles.heading(
                          color: theme.onSurface,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children:
                          options
                              .map(
                                (option) => ListTile(
                                  title: Text(
                                    option,
                                    style: AppTextStyles.body(
                                      color: theme.onSurface,
                                    ),
                                  ),
                                  trailing:
                                      option == current
                                          ? Icon(
                                            Icons.check,
                                            color: theme.accent,
                                          )
                                          : null,
                                  onTap: () => Navigator.pop(context, option),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  bool get _formIsValid =>
      _businessName.text.trim().isNotEmpty && _category != null && _state != null;

  Future<void> _submit() async {
    if (!_formIsValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in the business name, category and state')),
      );
      return;
    }

    setState(() => _submitting = true);
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      String? logoUrl;
      final logo = _logo;
      if (logo != null && logo.isImage) {
        logoUrl = await appState.uploads.upload(file: logo, folder: 'vendor-logos');
      }

      await appState.vendors.create(
        businessName: _businessName.text.trim(),
        category: _category!,
        state: _state!,
        rcNumber: _rcNumber.text.trim().isEmpty ? null : _rcNumber.text.trim(),
        logoUrl: logoUrl,
      );
      appState.markVendorProfileCreated();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VendorDashboardScreen(theme: widget.theme)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text(
          'Become a Vendor',
          style: AppTextStyles.heading(color: theme.foreground, size: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: ResponsiveCenter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tell us about your business',
                  style: AppTextStyles.body(
                    color: theme.foreground.withValues(alpha: 0.65),
                    size: 14,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: _pickLogo,
                  child: Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: theme.accent.withValues(alpha: 0.15),
                          backgroundImage:
                              _logo != null && _logo!.isImage
                                  ? _logo!.imageProvider
                                  : null,
                          child:
                              _logo == null
                                  ? Icon(
                                    Icons.storefront_rounded,
                                    size: 34,
                                    color: theme.accent,
                                  )
                                  : (_logo!.isImage
                                      ? null
                                      : Icon(
                                        Icons.insert_drive_file_rounded,
                                        size: 30,
                                        color: theme.accent,
                                      )),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _logo?.fileName ?? 'Add a Business Logo (optional)',
                          style: AppTextStyles.body(
                            color: theme.accent,
                            weight: FontWeight.w600,
                            size: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _Field(
                  label: 'Business Name',
                  theme: theme,
                  controller: _businessName,
                  hint: 'e.g. Comfort Home Furniture',
                ),
                const SizedBox(height: 16),
                _Dropdown(
                  label: 'Business Category',
                  theme: theme,
                  value: _category?.label ?? 'Select a category',
                  onTap: _pickCategory,
                ),
                const SizedBox(height: 16),
                _Dropdown(
                  label: 'State',
                  theme: theme,
                  value: _state ?? 'Select your state',
                  onTap: _pickState,
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'CAC/RC Number (optional)',
                  theme: theme,
                  controller: _rcNumber,
                  keyboardType: TextInputType.text,
                  hint: 'e.g. RC1234567',
                ),
                const SizedBox(height: 24),
                PillButton(
                  label: _submitting ? 'Setting up your shop…' : 'Create My Shop',
                  backgroundColor: theme.accent,
                  textColor: theme.onAccent,
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.theme,
    required this.controller,
    this.keyboardType,
    this.hint = '',
  });

  final String label;
  final DashboardTheme theme;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return LabeledPillField(
      label: label,
      labelColor: theme.foreground,
      labelSize: 13.5,
      controller: controller,
      keyboardType: keyboardType,
      hint: hint,
      fillColor: theme.surface,
      textColor: theme.onSurface,
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.theme,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DashboardTheme theme;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body(
            color: theme.foreground,
            weight: FontWeight.w600,
            size: 13.5,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: AppTextStyles.body(color: theme.onSurface, size: 15),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: theme.onSurface.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
