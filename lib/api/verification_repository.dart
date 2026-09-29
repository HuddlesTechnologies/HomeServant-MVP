import 'api_client.dart';
import 'models/platform_settings.dart';
import 'models/stuck_payment.dart';
import 'models/verification.dart';

/// Identity documents (backend VerificationController /
/// AdminVerificationController).
class VerificationRepository {
  VerificationRepository(this._client);

  final ApiClient _client;

  /// Any subset: signup sends the landlord certificate on step 1 and the ID
  /// (plus landlord document) on step 2.
  ///
  /// Returns the status the submission ended up at. Submitting an ID also
  /// has the server check the number with the body that issued it, so a
  /// tenant can come straight back [VerificationStatus.approved] instead
  /// of waiting for a moderator — the caller shouldn't assume "pending".
  Future<VerificationStatus?> update({IdDocumentType? idType, String? idNumber, String? certificatePath, String? documentPath}) =>
      _client.call(() async {
        final response = await _client.dio.patch('/verification/me', data: {
          if (idType != null) 'idType': idType.apiValue,
          if (idNumber != null) 'idNumber': idNumber,
          if (certificatePath != null) 'certificatePath': certificatePath,
          if (documentPath != null) 'documentPath': documentPath,
        });
        final data = response.data;
        return data is Map<String, dynamic> ? VerificationStatus.fromApi(data['status'] as String?) : null;
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

  /// Runs the ID number past the issuing body again — for a check that
  /// errored, or a submission made before checks existed. Costs a real
  /// lookup per call, and can verify a tenant on its own.
  Future<VerificationDetail> recheck(String userId) => _client.call(() async {
    final response = await _client.dio.post('/admin/verifications/user/$userId/recheck');
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

  Future<PlatformSettings> setPayUnverifiedLandlords(bool value) => _client.call(() async {
    final response = await _client.dio.patch('/admin/platform-settings', data: {'payUnverifiedLandlords': value});
    return PlatformSettings.fromApi(response.data as Map<String, dynamic>);
  });

  Future<PlatformSettings> setRequireVerifiedLandlords(bool value) => _client.call(() async {
    final response = await _client.dio.patch('/admin/platform-settings', data: {'requireVerifiedLandlords': value});
    return PlatformSettings.fromApi(response.data as Map<String, dynamic>);
  });

  /// Any other Platform Controls values (e.g. `maxListingImageChanges`).
  Future<PlatformSettings> updatePlatformSettings(Map<String, dynamic> values) => _client.call(() async {
    final response = await _client.dio.patch('/admin/platform-settings', data: values);
    return PlatformSettings.fromApi(response.data as Map<String, dynamic>);
  });

  // --- Payouts & refunds needing attention (moderator+) -----------------------

  Future<List<StuckPayment>> stuckPayments() => _client.call(() async {
    final response = await _client.dio.get('/admin/payouts');
    return (response.data as List).cast<Map<String, dynamic>>().map(StuckPayment.fromApi).toList();
  });

  /// HomeServant's Paystack balance in kobo — payouts are sent from it —
  /// null when Paystack couldn't be asked; and which balance it is: 'test'
  /// or 'live' (from the server key's prefix), or 'unknown'.
  Future<({int? balanceKobo, String mode})> paystackBalance() => _client.call(() async {
    final response = await _client.dio.get('/admin/payouts/balance');
    final data = response.data as Map<String, dynamic>;
    return (balanceKobo: data['balanceKobo'] as int?, mode: data['mode'] as String? ?? 'unknown');
  });

  Future<int> stuckPaymentCount() => _client.call(() async {
    final response = await _client.dio.get('/admin/payouts/count');
    return (response.data as Map<String, dynamic>)['count'] as int? ?? 0;
  });

  /// Returns 'PAID' or 'ALREADY_PAID'.
  Future<String> retryPayout(String paymentId) => _client.call(() async {
    final response = await _client.dio.post('/admin/payouts/$paymentId/retry');
    return (response.data as Map<String, dynamic>)['status'] as String? ?? 'PAID';
  });

  /// Returns 'REFUNDED' or 'ALREADY_REFUNDED'.
  Future<String> retryRefund(String paymentId) => _client.call(() async {
    final response = await _client.dio.post('/admin/payouts/$paymentId/retry-refund');
    return (response.data as Map<String, dynamic>)['status'] as String? ?? 'REFUNDED';
  });

  Future<void> refundTenant(String paymentId, String reason) => _client.call(() async {
    await _client.dio.post('/admin/payouts/$paymentId/refund-tenant', data: {'reason': reason});
  });
}
