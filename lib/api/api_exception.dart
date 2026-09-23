import 'package:dio/dio.dart';

/// Wraps the API's `{ statusCode, message, error }` error shape (see
/// backend/src/common/filters/http-exception.filter.ts) into something a
/// screen can show directly — `message` is already user-facing text.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  factory ApiException.fromDioError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final rawMessage = data['message'];
      final message = rawMessage is List ? rawMessage.join('\n') : rawMessage?.toString();
      return ApiException(error.response?.statusCode ?? 0, message ?? 'Something went wrong. Please try again.');
    }
    return ApiException(error.response?.statusCode ?? 0, 'Could not reach the server. Check your connection.');
  }

  @override
  String toString() => message;
}
