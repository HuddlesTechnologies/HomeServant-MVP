import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'web_session_storage_stub.dart' if (dart.library.html) 'web_session_storage_web.dart' as web_storage;

/// Access/refresh tokens live in the platform keychain, not
/// [SharedPreferences] — [AppState] used to store the user's raw password
/// there, which real tokens must not repeat.
///
/// On web there is no platform keychain, so [FlutterSecureStorage] falls
/// back to browser `localStorage` — which every tab/window on the same
/// origin shares. That let two different users signed in from two tabs on
/// the same browser silently bleed into each other's session (a tab left
/// open for user A would pick up user B's token as soon as B logged in
/// elsewhere and it made its next background request). So on web, tokens go
/// to `sessionStorage` instead — isolated per tab — via [web_storage].
class TokenStorage {
  TokenStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'hs_access_token';
  static const _refreshKey = 'hs_refresh_token';
  static const _appLockPinKey = 'hs_app_lock_pin';

  Future<String?> readAccessToken() async => kIsWeb ? web_storage.read(_accessKey) : _storage.read(key: _accessKey);
  Future<String?> readRefreshToken() async => kIsWeb ? web_storage.read(_refreshKey) : _storage.read(key: _refreshKey);

  Future<void> save({required String accessToken, required String refreshToken}) async {
    if (kIsWeb) {
      web_storage.write(_accessKey, accessToken);
      web_storage.write(_refreshKey, refreshToken);
      return;
    }
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      web_storage.remove(_accessKey);
      web_storage.remove(_refreshKey);
      return;
    }
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  /// The device app-lock PIN — kept here rather than in AppState's
  /// SharedPreferences blob for the same reason the tokens above are:
  /// SharedPreferences is a plaintext file/XML on disk, recoverable via
  /// `adb backup` or root access, which would defeat the app-lock entirely.
  Future<String?> readAppLockPin() => _storage.read(key: _appLockPinKey);
  Future<void> saveAppLockPin(String pin) => _storage.write(key: _appLockPinKey, value: pin);
  Future<void> clearAppLockPin() => _storage.delete(key: _appLockPinKey);
}
