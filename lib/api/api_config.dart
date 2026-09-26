import 'package:flutter/foundation.dart';

/// Base URL of the HomeServant API, e.g.
/// `flutter run --dart-define=API_BASE_URL=http://localhost:3000/api`.
/// Falls back to local dev so `flutter run`/`flutter test` without the
/// define still points somewhere sensible.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api',
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
