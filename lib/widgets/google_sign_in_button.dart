import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../api/api_exception.dart';
import '../core/theme/app_text_styles.dart';
import '../services/google_auth_service.dart';
import '../state/app_state.dart';
import '../models/user_role.dart';
import 'login_outcome_handler.dart';

/// "Continue with Google" button that runs the whole Google sign-in: gets
/// an ID token, calls [AppState.loginWithGoogle], handles the
/// reactivate-a-deactivated-account prompt, and reports the result. The
/// login and signup screens used to each carry an identical copy of this
/// flow.
///
/// On Android/iOS this is our own button, which opens the native account
/// picker. On web it renders Google's own button instead (the only web flow
/// that yields an ID token — see GoogleAuthService) and picks up each
/// completed sign-in from [GoogleAuthService.webIdTokens].
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({super.key, required this.onSignedIn, required this.onError, this.role});

  /// The page's role: a new account gets it, and an existing account of
  /// another role is refused (see AppState.loginWithGoogle).
  final UserRole? role;

  /// Called once the account is signed in (the caller decides where to go
  /// next, e.g. the profile-setup wizard for a first-time account).
  final VoidCallback onSignedIn;

  /// Called with a message to show, or null to clear a previous one when
  /// a new attempt starts.
  final ValueChanged<String?> onError;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  StreamSubscription<String>? _webTokens;
  bool _busy = false;

  Future<void> _signIn({String? idToken, bool reactivate = false}) async {
    setState(() => _busy = true);
    widget.onError(null);
    try {
      final outcome = await context.read<AppState>().loginWithGoogle(idToken: idToken, reactivate: reactivate, role: widget.role);
      if (!mounted || outcome == null) return;
      await handleLoginOutcome(
        context,
        outcome,
        onSuccess: widget.onSignedIn,
        onTwoFactor: () {},
        onReactivate: () => _signIn(reactivate: true),
      );
    } on ApiException catch (e) {
      if (mounted) widget.onError(e.message);
    } catch (e) {
      // Google SDK failures (misconfigured OAuth client, popup blocked,
      // network) used to escape this handler entirely, so the button
      // just stopped spinning with no explanation.
      debugPrint('Google sign-in failed: $e');
      if (mounted) widget.onError('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (GoogleAuthService.usesRenderedButton) {
      _webTokens = GoogleAuthService.webIdTokens.listen((token) {
        // go_router keeps earlier screens of the stack mounted (e.g. the
        // login screen under the signup screen), each with its own
        // button — only the one actually on top should act on a sign-in.
        if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        _signIn(idToken: token);
      });
    }
  }

  @override
  void dispose() {
    _webTokens?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (GoogleAuthService.usesRenderedButton) {
      return SizedBox(
        height: 56,
        child: Center(
          child: IgnorePointer(
            ignoring: _busy,
            child: GoogleAuthService.buildWebButton(),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _busy ? null : _signIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset('assets/icons/google_g.svg', width: 20, height: 20),
            const SizedBox(width: 10),
            Text('Continue with Google', style: AppTextStyles.body(color: const Color(0xFF1F1F1F), weight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
