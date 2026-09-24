import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/home_servant_logo.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/themed_scaffold.dart';

class SignupTenant1Screen extends StatefulWidget {
  const SignupTenant1Screen({super.key, required this.onContinue});

  final ValueChanged<Map<String, String>> onContinue;

  @override
  State<SignupTenant1Screen> createState() => _SignupTenant1ScreenState();
}

class _SignupTenant1ScreenState extends State<SignupTenant1Screen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _referral = TextEditingController();
  final _dob = TextEditingController();
  DateTime? _dateOfBirth;
  static const _role = UserRole.tenant;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _referral.dispose();
    _dob.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dob.text = formatShortDate(picked);
      });
    }
  }

  Future<void> _continue() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final referral = _referral.text.trim();
      await context.read<AppState>().completeProfile(
        fullName: _name.text.trim(),
        phoneNumber: _phone.text.trim(),
        dateOfBirth: _dateOfBirth,
        referralCode: referral.isEmpty ? null : referral,
      );
      if (!mounted) return;
      widget.onContinue({'name': _name.text.trim(), 'phone': _phone.text.trim(), 'referral': _referral.text.trim()});
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      role: _role,
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
          _Field(
            label: 'Enter your Name',
            color: _role.foreground,
            controller: _name,
            hint: 'Full name',
          ),
          const SizedBox(height: 18),
          _Field(
            label: 'Phone Number',
            color: _role.foreground,
            controller: _phone,
            keyboardType: TextInputType.phone,
            hint: 'e.g. 0801 234 5678',
          ),
          const SizedBox(height: 18),
          _Field(
            label: 'Date of Birth',
            color: _role.foreground,
            controller: _dob,
            hint: 'Tap to select a date',
            readOnly: true,
            onTap: _pickDate,
            trailing: const Icon(Icons.calendar_today_outlined, color: AppColors.navy, size: 18),
          ),
          const SizedBox(height: 18),
          _Field(
            label: 'Referral code (optional)',
            color: _role.foreground,
            controller: _referral,
            hint: 'HS-XXXXXX',
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
          ],
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
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.color,
    required this.controller,
    this.keyboardType,
    this.hint = '',
    this.readOnly = false,
    this.onTap,
    this.trailing,
  });

  final String label;
  final Color color;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String hint;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body(color: color, weight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        PillTextField(
          hint: hint,
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          onTap: onTap,
          trailing: trailing,
        ),
      ],
    );
  }
}
