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
            onSessionExpired?.call();
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
  void Function()? onSessionExpired;

  /// Shared by every concurrent 401 so only one actually calls
  /// `/auth/refresh` at a time. The backend's refresh token is single-use
  /// (it's rotated and revoked on success — see AuthService.refresh), so
  /// two requests 401-ing at the same moment and each independently
  /// calling this used to race: the first to land would rotate the token,
  /// and the second's attempt would then fail against the now-revoked one
  /// — spuriously triggering [onSessionExpired] even though the session
  /// was actually fine and new tokens were already saved by the first.
  Future<String?>? _refreshInFlight;

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
    } on DioException {
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
