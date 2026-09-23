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

class LoginTenantScreen extends StatefulWidget {
  const LoginTenantScreen({
    super.key,
    required this.onLoginSuccess,
    required this.onGoogleSignedIn,
    required this.onRequiresTwoFactor,
    required this.onSignUp,
    required this.onForgotPassword,
  });

  final VoidCallback onLoginSuccess;

  /// Distinct from [onLoginSuccess] — a first-time Google sign-in may need
  /// to collect a phone number Google never provided, so the router routes
  /// this case differently.
  final VoidCallback onGoogleSignedIn;
  final VoidCallback onRequiresTwoFactor;
  final VoidCallback onSignUp;
  final VoidCallback onForgotPassword;

  @override
  State<LoginTenantScreen> createState() => _LoginTenantScreenState();
}

class _LoginTenantScreenState extends State<LoginTenantScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  static const _role = UserRole.tenant;
  bool _submitting = false;
  bool _googleSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final loggedIn = await context.read<AppState>().login(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      if (loggedIn) {
        widget.onLoginSuccess();
      } else {
        widget.onRequiresTwoFactor();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      _googleSubmitting = true;
      _error = null;
    });
    try {
      final signedIn = await context.read<AppState>().loginWithGoogle();
      if (!mounted) return;
      if (signedIn) {
        widget.onGoogleSignedIn();
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _googleSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      role: _role,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(child: HomeServantLogo(role: _role, iconSize: 60)),
          const SizedBox(height: 64),
          PillTextField(hint: 'Email', controller: _email, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 16),
          PillTextField(hint: 'Password', controller: _password, obscureText: true),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: widget.onForgotPassword,
              child: Text(
                'Forgot Password?',
                style: AppTextStyles.body(color: _role.emphasis, weight: FontWeight.w600, size: 13),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          PillButton(
            label: _submitting ? 'Logging in…' : 'Login',
            backgroundColor: _role.accent,
            textColor: Colors.white,
            loading: _submitting,
            onPressed: _submitting ? null : _login,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Divider(color: _role.foreground.withValues(alpha: 0.4))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('or', style: AppTextStyles.body(color: _role.foreground.withValues(alpha: 0.7), size: 13)),
              ),
              Expanded(child: Divider(color: _role.foreground.withValues(alpha: 0.4))),
            ],
          ),
          const SizedBox(height: 20),
          GoogleSignInButton(onPressed: _googleSubmitting ? null : _loginWithGoogle),
          const SizedBox(height: 18),
          Center(
            child: GestureDetector(
              onTap: widget.onSignUp,
              child: RichText(
                text: TextSpan(
                  style: AppTextStyles.body(color: _role.foreground),
                  children: [
                    const TextSpan(text: "Don't have an account? "),
                    TextSpan(
                      text: 'Sign Up',
                      style: AppTextStyles.body(color: _role.emphasis, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 140),
          TermsFooter(
            mutedColor: _role.foreground.withValues(alpha: 0.55),
            linkColor: _role.foreground,
          ),
        ],
      ),
    );
  }
}
