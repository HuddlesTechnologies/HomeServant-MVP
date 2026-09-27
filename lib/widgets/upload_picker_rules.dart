import 'upload_picker.dart';

/// Identity documents must be a photo or a PDF (backend
/// SignVerificationUploadDto accepts the same).
bool isPhotoOrPdf(PickedUpload file) => file.isImage || file.fileName.toLowerCase().endsWith('.pdf');
