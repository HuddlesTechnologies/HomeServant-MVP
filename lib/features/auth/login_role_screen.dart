import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/home_servant_logo.dart';
import '../../widgets/login_outcome_handler.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/terms_footer.dart';
import '../../widgets/google_sign_in_button.dart';
import '../../api/models/auth_user.dart';
import '../../widgets/themed_scaffold.dart';

/// Login screen for either tenant or landlord accounts — the two were
/// identical line-for-line apart from which [UserRole] they used, so this
/// single screen is parameterized by [role] and used for both
/// `/login-landlord` and `/login-tenant`.
class LoginRoleScreen extends StatefulWidget {
  const LoginRoleScreen({
    super.key,
    required this.role,
    required this.onLoginSuccess,
    required this.onGoogleSignedIn,
    required this.onRequiresTwoFactor,
    required this.onRequiresEmailVerification,
    required this.onSignUp,
    required this.onForgotPassword,
  });

  final UserRole role;

  final VoidCallback onLoginSuccess;

  /// Distinct from [onLoginSuccess] — a first-time Google sign-in may need
  /// to collect a phone number Google never provided, so the router routes
  /// this case differently.
  final VoidCallback onGoogleSignedIn;
  final VoidCallback onRequiresTwoFactor;

  /// Correct password, but the account never entered its signup code — a
  /// fresh one has just been emailed.
  final VoidCallback onRequiresEmailVerification;
  final VoidCallback onSignUp;
  final VoidCallback onForgotPassword;

  @override
  State<LoginRoleScreen> createState() => _LoginRoleScreenState();
}

class _LoginRoleScreenState extends State<LoginRoleScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _error;

  /// Which sign-in page the last error sent the user to, if any.
  UserRole? get _wrongPageTarget {
    final error = _error ?? '';
    if (error.contains('landlord page')) return UserRole.landlord;
    if (error.contains('tenant page')) return UserRole.tenant;
    return null;
  }

  UserRole get _role => widget.role;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login({bool reactivate = false}) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final outcome = await context.read<AppState>().login(
        email: _email.text.trim(),
        password: _password.text,
        reactivate: reactivate,
        // Only this page's kind of account gets in.
        portal: widget.role.apiValue,
      );
      if (!mounted) return;
      // Tells the platform autofill service (Chrome's/iOS's save-password
      // prompt) the credentials just typed actually worked — without this,
      // browsers won't offer to save a password from a Flutter form since
      // they never see a real form submission to hang the offer on.
      TextInput.finishAutofillContext();
      await handleLoginOutcome(
        context,
        outcome,
        onSuccess: widget.onLoginSuccess,
        onTwoFactor: widget.onRequiresTwoFactor,
        onEmailVerification: widget.onRequiresEmailVerification,
        onReactivate: () => _login(reactivate: true),
      );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(child: HomeServantLogo(role: _role, iconSize: 60)),
          const SizedBox(height: 64),
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PillTextField(
                  hint: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                ),
                const SizedBox(height: 16),
                PillTextField(
                  hint: 'Password',
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                ),
              ],
            ),
          ),
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
            Text(_error!, style: AppTextStyles.body(color: _role.errorColor, size: 13), textAlign: TextAlign.center),
            // The server refused an account from the other side (see
            // backend assertPortalAllows): offer a one-tap switch.
            if (_wrongPageTarget case final target?)
              Center(
                child: TextButton(
                  onPressed: () => context.pushReplacement(target == UserRole.landlord ? '/login-landlord' : '/login-tenant'),
                  child: Text(
                    target == UserRole.landlord ? 'Go to landlord sign in' : 'Go to tenant sign in',
                    style: AppTextStyles.body(color: _role.foreground, size: 13.5, weight: FontWeight.w700).copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: _role.foreground,
                    ),
                  ),
                ),
              ),
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
          GoogleSignInButton(
            role: widget.role,
            onSignedIn: widget.onGoogleSignedIn,
            onError: (message) => setState(() => _error = message),
          ),
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
