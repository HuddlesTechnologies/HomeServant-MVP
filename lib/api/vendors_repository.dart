import 'api_client.dart';
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

  Future<VendorProfile> update({
    String? businessName,
    MarketplaceCategory? category,
    String? state,
    String? rcNumber,
    String? logoUrl,
    String? bankName,
    String? accountNumber,
    String? accountName,
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
          if (bankName != null) 'bankName': bankName,
          if (accountNumber != null) 'accountNumber': accountNumber,
          if (accountName != null) 'accountName': accountName,
          if (isActive != null) 'isActive': isActive,
        },
      );
      return VendorProfile.fromApi(response.data as Map<String, dynamic>);
    });
  }
}
