import 'dart:io' as io show File;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mime/mime.dart';
import '../widgets/upload_picker.dart';
import 'api_client.dart';

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

  Future<String> upload({required PickedUpload file, required String folder}) {
    return _client.call(() async {
      final signed = await _client.dio.post('/uploads/sign', data: {'fileName': file.fileName, 'folder': folder});
      final signedUrl = signed.data['signedUrl'] as String;
      final publicUrl = signed.data['publicUrl'] as String;

      final bytes = await _readBytes(file);
      final contentType = lookupMimeType(file.fileName) ?? 'application/octet-stream';
      await Dio().put(
        signedUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(headers: {Headers.contentTypeHeader: contentType, Headers.contentLengthHeader: bytes.length}),
      );
      return publicUrl;
    });
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
