import 'package:flutter/foundation.dart';

/// Base URL of the HomeServant API, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://localhost:3000/api`.
/// Falls back to local dev so `flutter run`/`flutter test` without the
/// define still points somewhere sensible.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
);

/// The Web OAuth client's id (see backend/.env's `GOOGLE_CLIENT_ID` and
/// web/index.html's `google-signin-client_id` meta tag, both already this
/// same value) — passed to `GoogleSignIn` as `serverClientId` so the
/// Android plugin actually requests an ID token. Without a `serverClientId`
/// (or a `google-services.json`, which this app has neither of) the
/// Android `google_sign_in` plugin skips requesting one entirely, so
/// `GoogleSignInAccount.authentication.idToken` comes back null and
/// sign-in silently no-ops. An OAuth client id isn't a secret — it's
/// already shipped in plaintext in web/index.html — so hardcoding this
/// default is safe.
const googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '35203907287-l3ff7lthn7qq1382o6f2neamvke2qaeu.apps.googleusercontent.com',
);

/// Called once from `main()`, before anything touches the network. A
/// release build shipped with a plaintext `API_BASE_URL` (e.g. a
/// misconfigured CI run that drops the `--dart-define`) would silently
/// send every request — including auth tokens — over cleartext, so this
/// fails loudly instead. `assert()` alone doesn't cover this: Flutter
/// strips asserts from release builds, which is exactly the build this
/// needs to guard.
void assertSecureApiBaseUrl() {
  if (!kDebugMode && !apiBaseUrl.startsWith('https://')) {
    throw StateError('Refusing to run a release build with a non-HTTPS API_BASE_URL: $apiBaseUrl');
  }
}
