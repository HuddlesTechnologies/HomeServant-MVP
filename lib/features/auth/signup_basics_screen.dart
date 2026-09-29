import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_theme.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/field_error_text.dart';
import '../../widgets/home_servant_logo.dart';
import '../../widgets/labeled_pill_field.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/themed_scaffold.dart';
import '../../widgets/upload_picker.dart';
import '../../widgets/upload_picker_rules.dart';

/// Signup step 1 ("Welcome Onboard": name, phone, date of birth) for both
/// tenants and landlords. Role differences: a tenant can enter a referral code; a landlord gives a
/// house address and can attach a certificate of ownership.
class SignupBasicsScreen extends StatefulWidget {
  const SignupBasicsScreen({super.key, required this.role, required this.onContinue});

  final UserRole role;
  final ValueChanged<Map<String, String>> onContinue;

  @override
  State<SignupBasicsScreen> createState() => _SignupBasicsScreenState();
}

class _SignupBasicsScreenState extends State<SignupBasicsScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _referral = TextEditingController();
  final _houseAddress = TextEditingController();
  final _dob = TextEditingController();
  DateTime? _dateOfBirth;
  PickedUpload? _certificate;
  UserRole get _role => widget.role;
  bool _submitting = false;
  String? _error;
  final _formKey = GlobalKey<FormState>();
  String? _dobError;
  String? _certificateError;

  static const _minimumAge = 18;

  static String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  /// Nigerian numbers: 0XXXXXXXXXX (11 digits) or +234XXXXXXXXXX.
  static String? _validatePhone(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (digits.isEmpty) return 'Enter your phone number';
    if (!RegExp(r'^(0\d{10}|\+?234\d{10})$').hasMatch(digits)) {
      return 'Enter a valid phone number, e.g. 0801 234 5678';
    }
    return null;
  }

  bool _validateAll() {
    final formValid = _formKey.currentState?.validate() ?? false;
    String? dobError;
    final dob = _dateOfBirth;
    if (dob == null) {
      dobError = 'Select your date of birth';
    } else {
      final now = DateTime.now();
      final eighteenth = DateTime(dob.year + _minimumAge, dob.month, dob.day);
      if (eighteenth.isAfter(now)) dobError = 'You must be at least $_minimumAge to sign up';
    }
    final certificate = _certificate;
    final certificateError = !_role.isLandlord
        ? null
        : certificate == null
        ? 'Upload your certificate of ownership'
        : (!isPhotoOrPdf(certificate) ? 'Upload a photo or a PDF of your certificate' : null);
    setState(() {
      _dobError = dobError;
      _certificateError = certificateError;
    });
    return formValid && dobError == null && certificateError == null;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _referral.dispose();
    _houseAddress.dispose();
    _dob.dispose();
    super.dispose();
  }

  Future<void> _pickCertificate() async {
    final picked = await pickUpload(context);
    if (picked != null) {
      setState(() {
        _certificate = picked;
        _certificateError = null;
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
      builder: AppTheme.datePickerBuilder,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dob.text = formatShortDate(picked);
        _dobError = null;
      });
    }
  }

  /// A landlord's certificate of ownership goes to the private bucket and
  /// is saved for admin review before the profile fields.
  Future<void> _continue() async {
    if (!_validateAll()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final referral = _referral.text.trim();
      final appState = context.read<AppState>();
      final certificate = _certificate;
      if (_role.isLandlord && certificate != null) {
        final path = await appState.uploads.uploadPrivateDocument(certificate);
        await appState.verification.update(certificatePath: path);
      }
      await appState.completeProfile(
        fullName: _name.text.trim(),
        phoneNumber: _phone.text.trim(),
        houseAddress: _role.isLandlord ? _houseAddress.text.trim() : null,
        dateOfBirth: _dateOfBirth,
        referralCode: _role.isLandlord || referral.isEmpty ? null : referral,
      );
      if (!mounted) return;
      widget.onContinue({
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        if (_role.isLandlord) 'houseAddress': _houseAddress.text.trim() else 'referral': referral,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      role: _role,
      child: Form(
        key: _formKey,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(child: HomeServantLogo(role: _role, iconSize: 56)),
          const SizedBox(height: 28),
          Text(
            'Welcome Onboard',
            textAlign: TextAlign.center,
            style: AppTextStyles.heading(color: _role.foreground, size: 24),
          ),
          const SizedBox(height: 28),
          LabeledPillField(
            label: 'Enter your Name',
            labelColor: _role.foreground,
            controller: _name,
            hint: 'Full name',
            errorColor: _role.errorColor,
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null,
          ),
          const SizedBox(height: 18),
          LabeledPillField(
            label: 'Phone Number',
            labelColor: _role.foreground,
            controller: _phone,
            keyboardType: TextInputType.phone,
            hint: 'e.g. 0801 234 5678',
            errorColor: _role.errorColor,
            validator: _validatePhone,
          ),
          const SizedBox(height: 18),
          if (_role.isLandlord) ...[
            LabeledPillField(
              label: 'House Address',
              labelColor: _role.foreground,
              controller: _houseAddress,
              hint: 'Street, area, city',
              errorColor: _role.errorColor,
              validator: (v) => _required(v, 'Enter your house address'),
            ),
            const SizedBox(height: 18),
          ],
          LabeledPillField(
            label: 'Date of Birth',
            labelColor: _role.foreground,
            controller: _dob,
            hint: 'Tap to select a date',
            readOnly: true,
            onTap: _pickDate,
            trailing: const Icon(Icons.calendar_today_outlined, color: AppColors.navy, size: 18),
          ),
          FieldErrorText(_dobError, color: _role.errorColor),
          if (_role.isLandlord) ...[
            const SizedBox(height: 22),
            PillOutlineButton(
              label: _certificate?.fileName ?? 'Certificate of Ownership',
              textColor: AppColors.navy,
              icon: Icons.upload_file_rounded,
              onPressed: _pickCertificate,
            ),
            FieldErrorText(_certificateError, color: _role.errorColor),
          ] else ...[
            const SizedBox(height: 18),
            LabeledPillField(
              label: 'Referral code (optional)',
              labelColor: _role.foreground,
              controller: _referral,
              hint: 'HS-XXXXXX',
            ),
          ],
          FieldErrorText(_error, color: _role.errorColor, textAlign: TextAlign.center),
          const SizedBox(height: 28),
          PillButton(
            label: _submitting ? 'Saving…' : 'Continue',
            backgroundColor: _role.accent,
            textColor: Colors.white,
            loading: _submitting,
            onPressed: _submitting ? null : _continue,
          ),
          const SizedBox(height: 24),
        ],
        ),
      ),
    );
  }
}
