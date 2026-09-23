import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/home_servant_logo.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/terms_footer.dart';
import '../../widgets/themed_scaffold.dart';

class SignupTenantScreen extends StatefulWidget {
  const SignupTenantScreen({super.key, required this.onContinue});

  final ValueChanged<String> onContinue;

  @override
  State<SignupTenantScreen> createState() => _SignupTenantScreenState();
}

class _SignupTenantScreenState extends State<SignupTenantScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  static const _role = UserRole.tenant;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      await context.read<AppState>().signup(email: email, password: _password.text);
      if (!mounted) return;
      widget.onContinue(email);
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Center(child: HomeServantLogo(role: _role, iconSize: 60)),
            const SizedBox(height: 40),
            Text('Sign Up', textAlign: TextAlign.center, style: AppTextStyles.heading(color: _role.foreground, size: 30)),
            const SizedBox(height: 6),
            Text(
              'Enter your email and a password to sign up',
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: _role.foreground.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 28),
            PillTextField(
              hint: 'email@domain.com',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || !value.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 14),
            PillTextField(
              hint: 'Password',
              controller: _password,
              obscureText: true,
              validator: (value) {
                if (value == null || value.length < 8) return 'At least 8 characters';
                return null;
              },
            ),
            const SizedBox(height: 14),
            PillTextField(
              hint: 'Confirm password',
              controller: _confirmPassword,
              obscureText: true,
              validator: (value) {
                if (value != _password.text) return "Passwords don't match";
                return null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 18),
            PillButton(
              label: _submitting ? 'Signing up…' : 'Continue',
              backgroundColor: _role.accent,
              textColor: Colors.white,
              loading: _submitting,
              onPressed: _submitting ? null : _continue,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Divider(color: _role.foreground.withValues(alpha: 0.4))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Sign in with social media',
                    style: AppTextStyles.body(color: _role.foreground.withValues(alpha: 0.7), size: 13),
                  ),
                ),
                Expanded(child: Divider(color: _role.foreground.withValues(alpha: 0.4))),
              ],
            ),
            const SizedBox(height: 24),
            GoogleSignInButton(
              onPressed: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text("Google sign-in isn't available yet"))),
            ),
            const SizedBox(height: 140),
            TermsFooter(
              mutedColor: _role.foreground.withValues(alpha: 0.55),
              linkColor: _role.foreground,
            ),
          ],
        ),
      ),
    );
  }
}
