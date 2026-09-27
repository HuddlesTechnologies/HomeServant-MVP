import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Google's own rendered "Continue with Google" button (Google Identity
/// Services). On web this is the only sign-in entry point that hands back
/// an ID token — `GoogleSignIn.signIn()` there only opens an OAuth popup
/// that returns an access token, so `authentication.idToken` is always
/// null and our backend (which verifies an ID token) has nothing to check.
/// The resulting account arrives on `GoogleSignIn.onCurrentUserChanged`,
/// see GoogleAuthService.webIdTokens.
Widget buildGoogleWebButton() => web.renderButton(
      configuration: web.GSIButtonConfiguration(
        type: web.GSIButtonType.standard,
        theme: web.GSIButtonTheme.outline,
        size: web.GSIButtonSize.large,
        text: web.GSIButtonText.continueWith,
        shape: web.GSIButtonShape.pill,
        minimumWidth: 280,
      ),
    );
