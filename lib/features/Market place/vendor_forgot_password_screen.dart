import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import 'vendor_reset_password_screen.dart';

/// First step of the vendor password-reset flow, reached from
/// [VendorLoginScreen]. Always proceeds on success — the backend responds
/// the same way whether or not the email has an account, so this screen
/// can't tell the difference either (see AuthService.forgotPassword).
class VendorForgotPasswordScreen extends StatefulWidget {
  const VendorForgotPasswordScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorForgotPasswordScreen> createState() => _VendorForgotPasswordScreenState();
}

class _VendorForgotPasswordScreenState extends State<VendorForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<AppState>().forgotPassword(email);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VendorResetPasswordScreen(theme: widget.theme, email: email)),
      );
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
                const SizedBox(height: 20),
                Text('Forgot Password?', textAlign: TextAlign.center, style: AppTextStyles.heading(color: theme.foreground, size: 24)),
                const SizedBox(height: 10),
                Text(
                  "Enter the email on your vendor account and we'll send you a code to reset your password.",
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.65), size: 14),
                ),
                const SizedBox(height: 32),
                PillTextField(
                  hint: 'Email Address',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  fillColor: theme.surface,
                  textColor: theme.onSurface,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                PillButton(
                  label: _submitting ? 'Sending…' : 'Send Reset Code',
                  backgroundColor: theme.accent,
                  textColor: theme.onAccent,
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
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
