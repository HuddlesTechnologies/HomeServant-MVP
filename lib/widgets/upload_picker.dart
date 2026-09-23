import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

const _imageExtensions = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'gif', 'bmp'};

/// An [ImageProvider] for a locally-picked file path — a real file path on
/// mobile/desktop, or a blob URL on web (what `image_picker` returns there).
/// `dart:io.File` can't be constructed on web at all, so it must stay behind
/// the [kIsWeb] check rather than being called unconditionally. A `http(s)`
/// URL (a property/profile photo persisted from the API) is always a
/// [NetworkImage] regardless of platform — only a freshly-picked local file
/// needs the web/non-web split.
ImageProvider imageProviderForPath(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return NetworkImage(path);
  return kIsWeb ? NetworkImage(path) : FileImage(File(path));
}

/// Result of a successful upload pick, regardless of source.
class PickedUpload {
  const PickedUpload({required this.path, required this.fileName, required this.isImage, this.bytes});

  final String path;
  final String fileName;
  final bool isImage;

  /// Populated when the platform can't expose a readable file path — web's
  /// "Choose from Files" picker never returns a [path], only bytes.
  final Uint8List? bytes;

  /// An [ImageProvider] for this upload, preferring [bytes] (needed on web
  /// for files picked via "Choose from Files") and falling back to [path].
  ImageProvider get imageProvider {
    final data = bytes;
    return data != null ? MemoryImage(data) : imageProviderForPath(path);
  }
}

/// Lets the user upload any document — a photo from their camera roll, or
/// any file (PDF, Word doc, image, etc.) from Files. Used by every upload
/// affordance across the signup flow (profile photo, certificate of
/// ownership, ID/verification documents).
Future<PickedUpload?> pickUpload(BuildContext context) async {
  final source = await showModalBottomSheet<_UploadSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: AppColors.navy),
            title: Text('Choose from Camera Roll', style: AppTextStyles.body(color: AppColors.navy)),
            onTap: () => Navigator.pop(context, _UploadSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.folder_rounded, color: AppColors.navy),
            title: Text('Choose from Files', style: AppTextStyles.body(color: AppColors.navy)),
            onTap: () => Navigator.pop(context, _UploadSource.files),
          ),
        ],
      ),
    ),
  );

  switch (source) {
    case _UploadSource.gallery:
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return null;
      return PickedUpload(path: picked.path, fileName: picked.name, isImage: true);
    case _UploadSource.files:
      final result = await FilePicker.pickFiles(withData: true);
      final file = result?.files.single;
      if (file == null) return null;
      final extension = (file.extension ?? '').toLowerCase();
      return PickedUpload(
        path: file.path ?? file.name,
        fileName: file.name,
        isImage: _imageExtensions.contains(extension),
        bytes: file.bytes,
      );
    case null:
      return null;
  }
}

/// Lets the user pick several images at once (from the camera roll or
/// Files), up to [maxCount]. Used by the marketplace's "List a Product"
/// form, which needs 2-5 photos rather than one upload at a time.
Future<List<PickedUpload>> pickMultipleImageUploads(BuildContext context, {required int maxCount}) async {
  final source = await showModalBottomSheet<_UploadSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: AppColors.navy),
            title: Text('Choose from Camera Roll', style: AppTextStyles.body(color: AppColors.navy)),
            onTap: () => Navigator.pop(context, _UploadSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.folder_rounded, color: AppColors.navy),
            title: Text('Choose from Files', style: AppTextStyles.body(color: AppColors.navy)),
            onTap: () => Navigator.pop(context, _UploadSource.files),
          ),
        ],
      ),
    ),
  );

  switch (source) {
    case _UploadSource.gallery:
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85, limit: maxCount);
      return picked.map((f) => PickedUpload(path: f.path, fileName: f.name, isImage: true)).toList();
    case _UploadSource.files:
      final result = await FilePicker.pickFiles(withData: true, allowMultiple: true);
      final files = (result?.files ?? const []).take(maxCount);
      return files.map((file) {
        final extension = (file.extension ?? '').toLowerCase();
        return PickedUpload(
          path: file.path ?? file.name,
          fileName: file.name,
          isImage: _imageExtensions.contains(extension),
          bytes: file.bytes,
        );
      }).toList();
    case null:
      return const [];
  }
}

/// Lets the user pick a single video from their camera roll — used by the
/// landlord's Add Property form for an optional walkthrough clip.
///
/// Deliberately camera-roll-only, unlike [pickUpload]: `video_player` (what
/// plays the result back) can only load a file, a network URL, or a blob
/// URL — never raw bytes. `image_picker`'s gallery source reliably returns
/// a real path on mobile/desktop and a playable blob URL on web, but
/// `file_picker`'s "Choose from Files" is documented (see [PickedUpload])
/// to return *only* bytes on web with no path at all, which would leave a
/// web-picked file with nothing `video_player` could actually play.
Future<PickedUpload?> pickVideoUpload() async {
  final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
  if (picked == null) return null;
  return PickedUpload(path: picked.path, fileName: picked.name, isImage: false);
}

enum _UploadSource { gallery, files }
