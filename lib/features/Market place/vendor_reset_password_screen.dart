import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/otp_input_row.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';

/// Second step of the vendor password-reset flow — the code from
/// [VendorForgotPasswordScreen] plus a new password. Resetting signs out
/// every other session server-side (see AuthService.resetPassword), so
/// this always routes back to a normal login rather than logging the
/// vendor straight in.
class VendorResetPasswordScreen extends StatefulWidget {
  const VendorResetPasswordScreen({super.key, required this.theme, required this.email});

  final DashboardTheme theme;
  final String email;

  @override
  State<VendorResetPasswordScreen> createState() => _VendorResetPasswordScreenState();
}

class _VendorResetPasswordScreenState extends State<VendorResetPasswordScreen> {
  static const _startSeconds = 50;
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  int _secondsLeft = _startSeconds;
  Timer? _timer;
  String _code = '';
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _startSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await context.read<AppState>().forgotPassword(widget.email);
      if (!mounted) return;
      _startTimer();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset — log in with your new password')),
      );
      // ForgotPassword pushed this screen as its own replacement (see
      // VendorForgotPasswordScreen._submit), so the login screen that
      // started this flow is directly below it — a single pop lands
      // back there.
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ResponsiveCenter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Text('Reset Password', textAlign: TextAlign.center, style: AppTextStyles.heading(color: theme.foreground, size: 24)),
                const SizedBox(height: 8),
                Text(
                  'Enter the code sent to ${widget.email} and choose a new password.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.65), size: 14),
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Enter Code', style: AppTextStyles.body(color: theme.foreground, weight: FontWeight.w600)),
                    Text(
                      '0:${_secondsLeft.toString().padLeft(2, '0')}',
                      style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                OtpInputRow(
                  boxColor: theme.surface,
                  textColor: theme.onSurface,
                  onChanged: (value) => setState(() => _code = value),
                ),
                const SizedBox(height: 20),
                PillTextField(
                  hint: 'New Password',
                  controller: _newPassword,
                  obscureText: _obscureNew,
                  fillColor: theme.surface,
                  textColor: theme.onSurface,
                  trailing: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: theme.onSurface.withValues(alpha: 0.6),
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
                  fillColor: theme.surface,
                  textColor: theme.onSurface,
                  trailing: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: theme.onSurface.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                PillButton(
                  label: _submitting ? 'Resetting…' : 'Reset Password',
                  backgroundColor: theme.accent,
                  textColor: theme.onAccent,
                  loading: _submitting,
                  onPressed: _code.length == 4 && !_submitting ? _submit : null,
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _secondsLeft == 0 && !_resending ? _resend : null,
                    child: Text(
                      _secondsLeft == 0 ? 'Resend Code' : 'Resend available after timer ends',
                      style: AppTextStyles.body(
                        color: _secondsLeft == 0 ? theme.accent : theme.foreground.withValues(alpha: 0.4),
                        weight: FontWeight.w600,
                        size: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
