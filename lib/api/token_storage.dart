import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Access/refresh tokens live in the platform keychain, not
/// [SharedPreferences] — [AppState] used to store the user's raw password
/// there, which real tokens must not repeat.
class TokenStorage {
  TokenStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'hs_access_token';
  static const _refreshKey = 'hs_refresh_token';
  static const _appLockPinKey = 'hs_app_lock_pin';

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> save({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  Future<void> clear() async {
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
