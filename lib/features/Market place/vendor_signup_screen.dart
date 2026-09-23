import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/vendor.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/upload_picker.dart';
import '../dashboard/models/property.dart';
import 'vendor_verify_otp_screen.dart';

class VendorSignupScreen extends StatefulWidget {
  const VendorSignupScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorSignupScreen> createState() => _VendorSignupScreenState();
}

class _VendorSignupScreenState extends State<VendorSignupScreen> {
  final _businessName = TextEditingController();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _rcNumber = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  MarketplaceCategory? _category;
  String? _state;
  PickedUpload? _logo;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  bool _submitting = false;

  @override
  void dispose() {
    _businessName.dispose();
    _ownerName.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    _rcNumber.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
    if (result != null)
      setState(() => _category = MarketplaceCategoryApi.fromLabel(result));
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
      _businessName.text.trim().isNotEmpty &&
      _ownerName.text.trim().isNotEmpty &&
      _email.text.trim().contains('@') &&
      _phone.text.trim().isNotEmpty &&
      _category != null &&
      _address.text.trim().isNotEmpty &&
      _state != null &&
      _password.text.length >= 8 &&
      _agreedToTerms;

  Future<void> _submit() async {
    if (!_formIsValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please fill in all required fields (password at least 8 characters) and accept the vendor terms',
          ),
        ),
      );
      return;
    }
    if (_password.text != _confirmPassword.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() => _submitting = true);
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      appState.selectRole(UserRole.vendor);
      final email = _email.text.trim();
      await appState.signup(
        email: email,
        password: _password.text,
        fullName: _ownerName.text.trim(),
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => VendorVerifyOtpScreen(
                theme: widget.theme,
                email: email,
                businessName: _businessName.text.trim(),
                category: _category!,
                state: _state!,
                rcNumber: _rcNumber.text.trim(),
                phone: _phone.text.trim(),
                logo: _logo,
              ),
        ),
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
                _Field(
                  label: "Owner's Full Name",
                  theme: theme,
                  controller: _ownerName,
                  hint: 'Full name',
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Email Address',
                  theme: theme,
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  hint: 'Enter your email',
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Phone Number',
                  theme: theme,
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  hint: 'e.g. 0801 234 5678',
                ),
                const SizedBox(height: 16),
                _Dropdown(
                  label: 'Business Category',
                  theme: theme,
                  value: _category?.label ?? 'Select a category',
                  onTap: _pickCategory,
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Business Address',
                  theme: theme,
                  controller: _address,
                  minLines: 2,
                  maxLines: 3,
                  hint: 'Street, area, city',
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
                const SizedBox(height: 16),
                _Field(
                  label: 'Password',
                  theme: theme,
                  controller: _password,
                  obscureText: _obscurePassword,
                  hint: 'At least 8 characters',
                  trailing: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: theme.onSurface.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Confirm Password',
                  theme: theme,
                  controller: _confirmPassword,
                  obscureText: _obscureConfirm,
                  hint: 'Re-enter your password',
                  trailing: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: theme.onSurface.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    onPressed:
                        () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: _agreedToTerms,
                        activeColor: theme.accent,
                        onChanged:
                            (value) =>
                                setState(() => _agreedToTerms = value ?? false),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            'I agree to the Home Servant Vendor Terms & Conditions',
                            style: AppTextStyles.body(
                              color: theme.foreground.withValues(alpha: 0.75),
                              size: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PillButton(
                  label: _submitting ? 'Signing up…' : 'Sign Up as a Vendor',
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
    this.obscureText = false,
    this.trailing,
    this.minLines,
    this.maxLines = 1,
    this.hint = '',
  });

  final String label;
  final DashboardTheme theme;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? trailing;
  final int? minLines;
  final int? maxLines;
  final String hint;

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
        PillTextField(
          hint: hint,
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          trailing: trailing,
          minLines: minLines,
          maxLines: obscureText ? 1 : maxLines,
          fillColor: theme.surface,
          textColor: theme.onSurface,
        ),
      ],
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
