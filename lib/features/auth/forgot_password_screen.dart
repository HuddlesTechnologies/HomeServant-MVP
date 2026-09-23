import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/home_servant_logo.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/themed_scaffold.dart';

/// First step of the password-reset flow — collects the account email and
/// requests a reset code. Always proceeds to [onCodeSent] on success (the
/// backend responds the same way whether or not that email has an
/// account, so this screen can't tell the difference either — see
/// AuthService.forgotPassword).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, required this.role, required this.onCodeSent});

  final UserRole role;
  final ValueChanged<String> onCodeSent;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
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
      widget.onCodeSent(email);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role;
    return ThemedScaffold(
      role: role,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(child: HomeServantLogo(role: role, iconSize: 56)),
          const SizedBox(height: 40),
          Text('Forgot Password?', textAlign: TextAlign.center, style: AppTextStyles.heading(color: role.foreground, size: 26)),
          const SizedBox(height: 10),
          Text(
            "Enter the email on your account and we'll send you a code to reset your password.",
            textAlign: TextAlign.center,
            style: AppTextStyles.body(color: role.foreground.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 32),
          PillTextField(
            hint: 'Email',
            controller: _email,
            keyboardType: TextInputType.emailAddress,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          PillButton(
            label: _submitting ? 'Sending…' : 'Send Reset Code',
            backgroundColor: role.accent,
            textColor: Colors.white,
            loading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                'Back to Login',
                style: AppTextStyles.body(color: role.emphasis, weight: FontWeight.w600, size: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
