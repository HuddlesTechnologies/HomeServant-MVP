import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../api/api_config.dart';
import 'google_web_button_stub.dart' if (dart.library.js_interop) 'google_web_button_web.dart';

/// Thin wrapper around the google_sign_in package — isolates the one
/// piece of this app that talks to Google's SDK directly, so the rest of
/// the app (AppState, AuthRepository) only ever deals in ID tokens.
///
/// Mobile and web get an ID token in different ways:
/// - Android/iOS: tap our own button → [signInAndGetIdToken] opens the
///   native account picker.
/// - Web: `signIn()` can't produce an ID token there (it's an OAuth
///   access-token popup), so the screen shows Google's own rendered
///   button instead ([buildWebButton]) and listens on [webIdTokens].
class GoogleAuthService {
  // serverClientId is required on Android: without it (or a
  // google-services.json, which this app doesn't have) the plugin never
  // requests an ID token at all, so signInAndGetIdToken() below silently
  // returned null and "Continue with Google" did nothing. It's not
  // supported on web (the web plugin asserts it's null) — there the
  // client id comes from web/index.html's google-signin-client_id meta tag.
  static final GoogleSignIn _instance = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: kIsWeb ? null : googleServerClientId,
  );

  /// True where the screen must show [buildWebButton] rather than our own
  /// tappable button.
  static bool get usesRenderedButton => kIsWeb;

  /// Returns the ID token to send to `POST /auth/google`, or null if the
  /// user closed the picker without choosing an account. Mobile only.
  static Future<String?> signInAndGetIdToken() async {
    final account = await _instance.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      // Used to be returned as null, indistinguishable from "user
      // cancelled" — so a misconfigured OAuth client just made the button
      // silently do nothing.
      throw StateError('Google did not return an ID token');
    }
    return idToken;
  }

  /// Web only: an ID token each time the user completes Google's rendered
  /// button flow.
  static Stream<String> get webIdTokens => _instance.onCurrentUserChanged
      .where((account) => account != null)
      .asyncMap((account) async => (await account!.authentication).idToken)
      .where((token) => token != null)
      .cast<String>();

  /// Web only: Google's rendered button. The web plugin only draws it once
  /// it's been initialized, which the google_sign_in facade does lazily on
  /// its first call — hence the harmless [GoogleSignIn.isSignedIn] here.
  static Widget buildWebButton() {
    _instance.isSignedIn();
    return buildGoogleWebButton();
  }

  static Future<void> signOut() => _instance.signOut();
}
