import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';

/// Deliberately not reachable from any tenant/landlord/vendor screen —
/// admin accounts are never self-registered (see AuthService.signup), so
/// there's no "Sign Up" link here either, just email + password.
///
/// No self-service "Forgot Password" either, unlike every other role's
/// login screen — AuthService.forgotPassword explicitly refuses ADMIN
/// accounts. A locked-out admin has to ask a SUPER_ADMIN/MODERATOR to
/// reset their password from the Admins tab instead (see
/// AdminService.requestAdminPasswordReset), which emails them a new
/// one-time temporary password.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key, required this.onLoginSuccess});

  final VoidCallback onLoginSuccess;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
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
      // So a 2FA challenge (which happens before AppState.role is known
      // for real — see AuthService.login) themes '/login-2fa' correctly
      // and routes back here afterward; verifyLoginTwoFactor overwrites
      // this with the account's real role once it succeeds, so a non-
      // admin account just lands on its own dashboard instead, same as a
      // normal login.
      context.read<AppState>().selectRole(UserRole.admin);
      final outcome = await context.read<AppState>().login(email: _email.text.trim(), password: _password.text);
      if (!mounted) return;
      switch (outcome) {
        case LoginOutcome.success:
          final role = context.read<AppState>().role;
          if (!role.isAdmin) {
            await context.read<AppState>().logout();
            if (!mounted) return;
            setState(() => _error = 'This account is not an admin account.');
            return;
          }
          widget.onLoginSuccess();
        case LoginOutcome.requiresTwoFactor:
          if (!mounted) return;
          context.push('/login-2fa');
        case LoginOutcome.requiresReactivation:
          setState(() => _error = 'This account is deactivated. Contact another admin to reactivate it.');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.gold, size: 36),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Admin Console',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heading(color: Colors.white, size: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in with your admin account',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 14),
                  ),
                  const SizedBox(height: 32),
                  PillTextField(hint: 'Email', controller: _email, keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 16),
                  PillTextField(
                    hint: 'Password',
                    controller: _password,
                    obscureText: _obscurePassword,
                    trailing: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.navy.withValues(alpha: 0.6),
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Forgot your password? Ask a super admin or moderator to reset it from the Admins tab.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.45), size: 12),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: AppTextStyles.body(color: Colors.redAccent.shade100, size: 13), textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  PillButton(
                    label: _submitting ? 'Signing in…' : 'Sign In',
                    backgroundColor: AppColors.gold,
                    textColor: AppColors.navy,
                    loading: _submitting,
                    onPressed: _submitting ? null : _login,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
