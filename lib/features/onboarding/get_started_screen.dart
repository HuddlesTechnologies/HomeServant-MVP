import 'package:flutter/material.dart';
import '../../widgets/two_choice_screen.dart';

class GetStartedScreen extends StatelessWidget {
  const GetStartedScreen({super.key, required this.onLogin, required this.onSignUp});

  final VoidCallback onLogin;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    return TwoChoiceScreen(
      title: 'Get Started with\nHome Servant',
      subtitle: 'Find your dream home or manage your properties with ease.',
      primaryLabel: 'Login',
      onPrimary: onLogin,
      secondaryLabel: 'Sign Up',
      onSecondary: onSignUp,
    );
  }
}
