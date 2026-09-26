import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/otp_input_row.dart';
import '../../widgets/otp_resend_controller.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/themed_scaffold.dart';

/// Second step of the password-reset flow — the code from
/// [ForgotPasswordScreen] plus a new password. On success the account's
/// other sessions are signed out server-side (see AuthService.resetPassword),
/// so this always routes back to a normal login rather than logging the
/// user straight in.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.role, required this.email, required this.onReset});

  final UserRole role;
  final String email;
  final VoidCallback onReset;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  String _code = '';
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<bool> _resend() async {
    try {
      await context.read<AppState>().forgotPassword(widget.email);
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    }
  }

  Future<void> _submit() async {
    if (_code.length != 4) {
      setState(() => _error = 'Enter the 4-digit code sent to your email');
      return;
    }
    if (_newPassword.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AppState>().resetPassword(email: widget.email, code: _code, newPassword: _newPassword.text);
      if (!mounted) return;
      // See LoginRoleScreen — lets the browser/iOS offer to update the
      // saved credential with the new password.
      TextInput.finishAutofillContext();
      widget.onReset();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    final boxColor = role.isLandlord ? AppColors.offWhite : const Color(0xFF7C859C);
    return ThemedScaffold(
      role: role,
      child: OtpResendController(
        onResend: _resend,
        builder: (context, secondsLeft, resending, onResendPressed) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text('Reset Password', textAlign: TextAlign.center, style: AppTextStyles.heading(color: role.foreground, size: 26)),
            const SizedBox(height: 8),
            Text(
              'Enter the code sent to ${widget.email} and choose a new password.',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: role.foreground.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Enter Code', style: AppTextStyles.body(color: role.foreground, weight: FontWeight.w600)),
                Text(
                  '0:${secondsLeft.toString().padLeft(2, '0')}',
                  style: AppTextStyles.body(color: role.foreground.withValues(alpha: 0.7), size: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OtpInputRow(
              boxColor: boxColor,
              textColor: role.isLandlord ? AppColors.navy : AppColors.white,
              onChanged: (value) => setState(() => _code = value),
            ),
            const SizedBox(height: 20),
            AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PillTextField(
                    hint: 'New Password',
                    controller: _newPassword,
                    obscureText: _obscureNew,
                    autofillHints: const [AutofillHints.newPassword],
                    trailing: IconButton(
                      icon: Icon(
                        _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: role.foreground.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                  const SizedBox(height: 16),
                  PillTextField(
                    hint: 'Confirm New Password',
                    controller: _confirmPassword,
                    obscureText: _obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    trailing: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: role.foreground.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            PillButton(
              label: _submitting ? 'Resetting…' : 'Reset Password',
              backgroundColor: role.accent,
              textColor: Colors.white,
              loading: _submitting,
              onPressed: _code.length == 4 && !_submitting ? _submit : null,
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: onResendPressed,
                child: Text(
                  secondsLeft == 0 ? 'Resend Code' : 'Resend available after timer ends',
                  style: AppTextStyles.body(
                    color: secondsLeft == 0 ? role.emphasis : role.foreground.withValues(alpha: 0.4),
                    weight: FontWeight.w600,
                    size: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
