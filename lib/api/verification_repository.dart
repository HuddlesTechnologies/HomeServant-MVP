import 'api_client.dart';
import 'models/platform_settings.dart';
import 'models/verification.dart';

/// Identity documents (backend VerificationController /
/// AdminVerificationController).
class VerificationRepository {
  VerificationRepository(this._client);

  final ApiClient _client;

  /// Any subset: signup sends the landlord certificate on step 1 and the ID
  /// (plus landlord document) on step 2.
  Future<void> update({IdDocumentType? idType, String? idNumber, String? certificatePath, String? documentPath}) =>
      _client.call(() async {
        await _client.dio.patch('/verification/me', data: {
          if (idType != null) 'idType': idType.apiValue,
          if (idNumber != null) 'idNumber': idNumber,
          if (certificatePath != null) 'certificatePath': certificatePath,
          if (documentPath != null) 'documentPath': documentPath,
        });
      });

  // --- Admin (moderator and above) ------------------------------------------

  Future<List<VerificationSummary>> list({VerificationStatus? status}) => _client.call(() async {
    final response = await _client.dio.get('/admin/verifications', queryParameters: {if (status != null) 'status': status.apiValue});
    return (response.data as List).cast<Map<String, dynamic>>().map(VerificationSummary.fromApi).toList();
  });

  Future<int> pendingCount() => _client.call(() async {
    final response = await _client.dio.get('/admin/verifications/pending-count');
    return (response.data as Map<String, dynamic>)['count'] as int? ?? 0;
  });

  Future<VerificationDetail> detail(String userId) => _client.call(() async {
    final response = await _client.dio.get('/admin/verifications/user/$userId');
    return VerificationDetail.fromApi(response.data as Map<String, dynamic>);
  });

  Future<VerificationDetail> review(String userId, {required bool approve, String? note}) => _client.call(() async {
    final response = await _client.dio.post(
      '/admin/verifications/user/$userId/review',
      data: {'decision': approve ? 'APPROVE' : 'REJECT', if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    return VerificationDetail.fromApi(response.data as Map<String, dynamic>);
  });

  // --- Platform Controls (super admin) ---------------------------------------

  Future<PlatformSettings> platformSettings() => _client.call(() async {
    final response = await _client.dio.get('/admin/platform-settings');
    return PlatformSettings.fromApi(response.data as Map<String, dynamic>);
  });

  Future<PlatformSettings> setRequireVerifiedLandlords(bool value) => _client.call(() async {
    final response = await _client.dio.patch('/admin/platform-settings', data: {'requireVerifiedLandlords': value});
    return PlatformSettings.fromApi(response.data as Map<String, dynamic>);
  });
}
