import 'package:google_sign_in/google_sign_in.dart';
import '../api/api_config.dart';

/// Thin wrapper around the google_sign_in package — isolates the one
/// piece of this app that talks to Google's SDK directly, so the rest of
/// the app (AppState, AuthRepository) only ever deals in ID tokens.
class GoogleAuthService {
  // serverClientId is required on Android: without it (or a
  // google-services.json, which this app doesn't have) the plugin never
  // requests an ID token at all, so signInAndGetIdToken() below silently
  // returned null and "Continue with Google" did nothing.
  static final GoogleSignIn _instance = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: googleServerClientId,
  );

  /// Returns the ID token to send to `POST /auth/google`, or null if the
  /// user closed the picker/popup without choosing an account.
  static Future<String?> signInAndGetIdToken() async {
    final account = await _instance.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.idToken;
  }

  static Future<void> signOut() => _instance.signOut();
}
