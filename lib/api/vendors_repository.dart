import 'package:dio/dio.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'models/vendor.dart';

class VendorsRepository {
  VendorsRepository(this._client);

  final ApiClient _client;

  Future<VendorProfile> create({
    required String businessName,
    required MarketplaceCategory category,
    required String state,
    String? rcNumber,
    String? logoUrl,
  }) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/vendors/me',
        data: {
          'businessName': businessName,
          'category': category.apiValue,
          'state': state,
          if (rcNumber != null && rcNumber.isNotEmpty) 'rcNumber': rcNumber,
          if (logoUrl != null) 'logoUrl': logoUrl,
        },
      );
      return VendorProfile.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<VendorProfile> me() {
    return _client.call(() async {
      final response = await _client.dio.get('/vendors/me');
      return VendorProfile.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Same as [me], but a 404 ("no vendor profile for this account yet" —
  /// see VendorsService.findMine) resolves to `null` instead of throwing.
  /// Used to check whether the signed-in account already has a shop, where
  /// "no profile" is an expected outcome rather than an error to surface.
  Future<VendorProfile?> findMine() async {
    try {
      final response = await _client.dio.get('/vendors/me');
      return VendorProfile.fromApi(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException.fromDioError(e);
    }
  }

  /// [bankCode]/[accountNumber] are the only bank-related inputs this takes
  /// — mirrors `PATCH /users/me/bank-details` (landlord): the server
  /// re-resolves the account against Paystack itself and returns the
  /// verified `accountName`/`bankName`, so a raw client-supplied
  /// `accountName` is never accepted or sent.
  Future<VendorProfile> update({
    String? businessName,
    MarketplaceCategory? category,
    String? state,
    String? rcNumber,
    String? logoUrl,
    String? bankCode,
    String? accountNumber,
    bool? isActive,
  }) {
    return _client.call(() async {
      final response = await _client.dio.patch(
        '/vendors/me',
        data: {
          if (businessName != null) 'businessName': businessName,
          if (category != null) 'category': category.apiValue,
          if (state != null) 'state': state,
          if (rcNumber != null) 'rcNumber': rcNumber,
          if (logoUrl != null) 'logoUrl': logoUrl,
          if (bankCode != null) 'bankCode': bankCode,
          if (accountNumber != null) 'accountNumber': accountNumber,
          if (isActive != null) 'isActive': isActive,
        },
      );
      return VendorProfile.fromApi(response.data as Map<String, dynamic>);
    });
  }
}
