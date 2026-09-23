import 'package:dio/dio.dart';
import '../models/user_role.dart';
import 'api_client.dart';
import 'models/auth_user.dart';
import 'token_storage.dart';

class LoginResult {
  const LoginResult({this.tokens, this.user, this.requiresTwoFactor = false});

  final ({String accessToken, String refreshToken})? tokens;
  final AuthUser? user;
  final bool requiresTwoFactor;
}

/// Wraps `/auth/*`. Every call that returns tokens also persists them to
/// [TokenStorage] before returning, so callers (AppState) just need to
/// react to the result, not remember to save anything.
class AuthRepository {
  AuthRepository(this._client, this._tokens);

  final ApiClient _client;
  final TokenStorage _tokens;

  Future<void> signup({required String email, required String password, required UserRole role, String? fullName}) {
    return _client.call(() async {
      await _client.dio.post(
        '/auth/signup',
        data: {'email': email, 'password': password, 'role': role.apiValue, if (fullName != null && fullName.isNotEmpty) 'fullName': fullName},
        options: Options(extra: {'skipAuth': true}),
      );
    });
  }

  Future<AuthUser> verifySignup({required String email, required String code}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/auth/verify-signup',
        data: {'email': email, 'code': code},
        options: Options(extra: {'skipAuth': true}),
      );
      return _saveTokensAndUser(response.data);
    });
  }

  Future<LoginResult> login({required String email, required String password}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
        options: Options(extra: {'skipAuth': true}),
      );
      final data = response.data as Map<String, dynamic>;
      if (data['requiresTwoFactor'] == true) {
        return const LoginResult(requiresTwoFactor: true);
      }
      final user = await _saveTokensAndUser(data);
      return LoginResult(user: user);
    });
  }

  /// [role] is only required when the Google account doesn't match an
  /// existing user yet — the backend creates one with it; an existing
  /// user just logs in regardless of which role screen this was tapped
  /// from.
  Future<AuthUser> googleAuth({required String idToken, required UserRole role}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/auth/google',
        data: {'idToken': idToken, 'role': role.apiValue},
        options: Options(extra: {'skipAuth': true}),
      );
      return _saveTokensAndUser(response.data);
    });
  }

  Future<AuthUser> verifyLoginTwoFactor({required String email, required String code}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/auth/verify-2fa',
        data: {'email': email, 'code': code},
        options: Options(extra: {'skipAuth': true}),
      );
      return _saveTokensAndUser(response.data);
    });
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) {
    return _client.call(() async {
      await _client.dio.patch('/auth/password', data: {'currentPassword': currentPassword, 'newPassword': newPassword});
    });
  }

  Future<void> logout() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken != null) {
      try {
        await _client.dio.post(
          '/auth/logout',
          data: {'refreshToken': refreshToken},
          options: Options(extra: {'skipAuth': true}),
        );
      } on DioException {
        // Best-effort — the server-side token gets cleaned up on its own
        // expiry even if this call fails; local logout must still proceed.
      }
    }
    await _tokens.clear();
  }

  Future<AuthUser> _saveTokensAndUser(Map<String, dynamic> data) async {
    await _tokens.save(accessToken: data['accessToken'] as String, refreshToken: data['refreshToken'] as String);
    return AuthUser.fromJson(data['user'] as Map<String, dynamic>);
  }
}
