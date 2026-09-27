import 'package:flutter/material.dart';
import '../../models/user_role.dart';
import '../../widgets/two_choice_screen.dart';

/// First step of the sign-up flow: asks which side of the marketplace the
/// visitor is signing up as before handing off to the role-specific form.
class SignupScreen extends StatelessWidget {
  const SignupScreen({super.key, required this.onRoleSelected});

  final ValueChanged<UserRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    return TwoChoiceScreen(
      title: 'Create an Account',
      subtitle: 'Tell us which side of Home Servant you\'re on.',
      primaryLabel: 'Sign up as a Tenant',
      onPrimary: () => onRoleSelected(UserRole.tenant),
      secondaryLabel: 'Sign up as a Landlord',
      onSecondary: () => onRoleSelected(UserRole.landlord),
    );
  }
}
