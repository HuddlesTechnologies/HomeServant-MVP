import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme/app_text_styles.dart';
import '../services/google_auth_service.dart';

/// Fully-rounded call-to-action button used for "Login" / "Continue" /
/// "Explore" throughout the prototype.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.textColor,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color textColor;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        child: loading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: textColor),
              )
            : Text(label, style: AppTextStyles.button(color: textColor)),
      ),
    );
  }
}

/// Secondary, outlined pill used for the "Certificate of Ownership" upload
/// action and similar white-on-white affordances.
class PillOutlineButton extends StatelessWidget {
  const PillOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.textColor,
    this.backgroundColor = Colors.white,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color textColor;
  final Color backgroundColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: textColor, size: 18),
              const SizedBox(width: 8),
            ],
            Text(label, style: AppTextStyles.button(color: textColor, size: 15)),
          ],
        ),
      ),
    );
  }
}

/// "Continue with Google" social button.
///
/// On Android/iOS this is our own button and [onPressed] opens the native
/// account picker. On web it renders Google's own button instead (the only
/// web flow that yields an ID token — see GoogleAuthService) and reports
/// each completed sign-in through [onWebIdToken]; [onPressed] is unused
/// there.
class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({super.key, required this.onPressed, required this.onWebIdToken});

  final VoidCallback? onPressed;
  final ValueChanged<String> onWebIdToken;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  StreamSubscription<String>? _webTokens;

  @override
  void initState() {
    super.initState();
    if (GoogleAuthService.usesRenderedButton) {
      _webTokens = GoogleAuthService.webIdTokens.listen((token) {
        // go_router keeps earlier screens of the stack mounted (e.g. the
        // login screen under the signup screen), each with its own
        // button — only the one actually on top should act on a sign-in.
        if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
        widget.onWebIdToken(token);
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
            ignoring: widget.onPressed == null,
            child: GoogleAuthService.buildWebButton(),
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: widget.onPressed,
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
