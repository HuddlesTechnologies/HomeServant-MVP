import 'package:flutter/material.dart';
import '../../models/user_role.dart';
import '../../widgets/two_choice_screen.dart';

/// First step of the login flow: asks which side of the marketplace the
/// visitor is logging in as before handing off to the role-specific form.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.onRoleSelected});

  final ValueChanged<UserRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    return TwoChoiceScreen(
      title: 'Welcome Back',
      subtitle: 'Tell us which side of Home Servant you\'re on.',
      primaryLabel: 'Login as a Tenant',
      onPrimary: () => onRoleSelected(UserRole.tenant),
      secondaryLabel: 'Login as a Landlord',
      onSecondary: () => onRoleSelected(UserRole.landlord),
    );
  }
}
