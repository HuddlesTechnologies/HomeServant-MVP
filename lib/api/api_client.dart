import 'dart:convert';

import 'package:dio/dio.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'token_storage.dart';

/// Thin wrapper around a single [Dio] instance, shared by every repository.
/// Attaches the access token to every request and transparently refreshes
/// it once on a 401 before retrying — callers just get a clean response or
/// an [ApiException].
class ApiClient {
  ApiClient(this._tokens) : dio = Dio(BaseOptions(baseUrl: apiBaseUrl, connectTimeout: const Duration(seconds: 15))) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokens.readAccessToken();
          if (token != null && !options.extra.containsKey('skipAuth')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final isAuthEndpoint = error.requestOptions.extra.containsKey('skipAuth');
          if (error.response?.statusCode == 401 && !isAuthEndpoint && !error.requestOptions.extra.containsKey('retried')) {
            final refreshed = await _tryRefresh();
            if (refreshed != null) {
              final retryOptions = error.requestOptions..extra['retried'] = true;
              retryOptions.headers['Authorization'] = 'Bearer $refreshed';
              try {
                final response = await dio.fetch(retryOptions);
                return handler.resolve(response);
              } on DioException catch (retryError) {
                return handler.next(retryError);
              }
            }
            onSessionExpired?.call(_bannedMessage);
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStorage _tokens;

  /// Set by [AppState] so a refresh-token failure (session truly expired,
  /// not just an access token due for renewal) clears local session state
  /// instead of leaving the app silently logged in with dead tokens.
  /// [bannedMessage] is the server's explanation when the session ended
  /// because the account was permanently banned (null otherwise).
  void Function(String? bannedMessage)? onSessionExpired;

  /// Set when the last refresh was refused because the account is banned.
  String? _bannedMessage;

  /// Shared by every concurrent 401 so only one actually calls
  /// `/auth/refresh` at a time. The backend's refresh token is single-use
  /// (it's rotated and revoked on success — see AuthService.refresh). If
  /// two requests that 401 at the same moment each refreshed, the second
  /// would fail against the token the first just revoked and sign the user
  /// out ([onSessionExpired]) although their session is fine.
  Future<String?>? _refreshInFlight;

  /// An access token that's good for at least another minute, refreshing
  /// first if the stored one has expired (or is about to). The chat socket
  /// calls this on every (re)connect: access tokens last 15 minutes, so a
  /// reconnect (network blip, laptop sleep, server restart) with the token
  /// from login would be rejected and live updates would stop.
  Future<String?> freshAccessToken() async {
    final token = await _tokens.readAccessToken();
    if (token == null) return null;
    final expiry = _expiryOf(token);
    if (expiry != null && expiry.isAfter(DateTime.now().add(const Duration(minutes: 1)))) return token;
    return _tryRefresh();
  }

  static DateTime? _expiryOf(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = (payload as Map<String, dynamic>)['exp'];
      return exp is int ? DateTime.fromMillisecondsSinceEpoch(exp * 1000) : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _tryRefresh() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() => _refreshInFlight = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _tokens.readRefreshToken();
    if (refreshToken == null) return null;
    try {
      final response = await dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'skipAuth': true}),
      );
      final accessToken = response.data['accessToken'] as String;
      final newRefreshToken = response.data['refreshToken'] as String;
      await _tokens.save(accessToken: accessToken, refreshToken: newRefreshToken);
      return accessToken;
    } on DioException catch (error) {
      // 403 on refresh means a ban (see backend assertNotBanned).
      _bannedMessage = error.response?.statusCode == 403 ? ApiException.fromDioError(error).message : null;
      await _tokens.clear();
      return null;
    }
  }

  /// Runs [request] and rethrows any failure as an [ApiException] with the
  /// server's message, so callers never need to know about Dio directly.
  Future<T> call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiException.fromDioError(error);
    }
  }
}
