import 'dart:io' as io show File;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mime/mime.dart';
import '../widgets/upload_picker.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// Uploads a picked file straight to Supabase Storage using a signed URL
/// minted by the API (`POST /uploads/sign`), then returns the file's public
/// URL to save on whatever record it belongs to (property image, profile
/// photo). This API never receives the file bytes itself.
///
/// NOTE: unverified against a live Supabase project — built from Supabase
/// Storage's documented signed-upload-URL contract (PUT the bytes straight
/// to `signedUrl` with a matching `Content-Type`), not exercised end to end
/// here. Re-check this once real Supabase credentials exist.
class UploadsRepository {
  UploadsRepository(this._client);

  final ApiClient _client;

  /// [maxBytes] refuses a bigger file up front with a clear message, rather
  /// than letting storage reject it mid-upload.
  Future<String> upload({required PickedUpload file, required String folder, int? maxBytes}) => _upload(
    file: file,
    signPath: '/uploads/sign',
    signBody: (name) => {'fileName': name, 'folder': folder},
    resultKey: 'publicUrl',
    maxBytes: maxBytes,
  );

  /// Identity documents (IDs, ownership certificates): photos or a PDF, into
  /// the PRIVATE bucket. Returns the object path to save — there is no
  /// public URL; admins view it through short-lived signed links.
  Future<String> uploadPrivateDocument(PickedUpload file) =>
      _upload(file: file, signPath: '/verification/uploads/sign', signBody: (name) => {'fileName': name}, resultKey: 'path');

  Future<String> _upload({
    required PickedUpload file,
    required String signPath,
    required Map<String, dynamic> Function(String fileName) signBody,
    required String resultKey,
    int? maxBytes,
  }) {
    return _client.call(() async {
      final Uint8List bytes;
      try {
        bytes = await _readBytes(file);
      } catch (_) {
        // On web this read goes to the picked file's blob: URL, which the
        // site's Content-Security-Policy must allow (connect-src blob:) —
        // when it didn't, this surfaced as a misleading "Could not reach
        // the server".
        throw ApiException(0, "Couldn't read the selected file. Please pick it again.");
      }
      if (maxBytes != null && bytes.length > maxBytes) {
        final mb = (maxBytes / (1024 * 1024)).round();
        throw ApiException(0, 'That file is too large — the limit is $mb MB. Please choose a shorter or smaller one.');
      }
      // Sniff the real type from the file's first bytes when the name alone
      // doesn't say (e.g. a web blob name with no extension) — the sign
      // endpoint rejects a fileName without an image extension, and the
      // backend later rejects anything Supabase doesn't serve as image/*.
      final contentType = lookupMimeType(file.fileName, headerBytes: bytes) ?? 'application/octet-stream';
      final fileName = _withExtension(file.fileName, contentType);

      final signed = await _client.dio.post(signPath, data: signBody(fileName));
      final signedUrl = signed.data['signedUrl'] as String;
      final result = signed.data[resultKey] as String;

      try {
        await Dio().put(
          signedUrl,
          // Browsers refuse a script-set Content-Length (they compute it
          // themselves), so it's only sent off-web.
          data: kIsWeb ? bytes : Stream.fromIterable([bytes]),
          options: Options(headers: {Headers.contentTypeHeader: contentType, if (!kIsWeb) Headers.contentLengthHeader: bytes.length}),
        );
      } on DioException {
        // Storage upload (straight to Supabase), not our API — say so
        // rather than the generic "Could not reach the server".
        throw ApiException(0, "Couldn't upload the file. Please try again.");
      }
      return result;
    });
  }

  static const _extensionByMime = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'image/gif': '.gif',
    'image/heic': '.heic',
    'image/heif': '.heif',
    'application/pdf': '.pdf',
    'video/mp4': '.mp4',
    'video/quicktime': '.mov',
    'video/x-m4v': '.m4v',
    'video/webm': '.webm',
  };

  static final _hasImageExtension = RegExp(r'\.(jpe?g|png|webp|heic|heif|gif|pdf|mp4|mov|m4v|webm)$', caseSensitive: false);

  String _withExtension(String fileName, String contentType) {
    if (_hasImageExtension.hasMatch(fileName)) return fileName;
    final extension = _extensionByMime[contentType];
    return extension == null ? fileName : '$fileName$extension';
  }

  Future<Uint8List> _readBytes(PickedUpload file) async {
    final bytes = file.bytes;
    if (bytes != null) return bytes;
    if (kIsWeb) {
      final response = await Dio().get<List<int>>(file.path, options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(response.data!);
    }
    return io.File(file.path).readAsBytes();
  }
}
