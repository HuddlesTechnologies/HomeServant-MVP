import 'api_client.dart';
import 'models/auth_user.dart';

class UsersRepository {
  UsersRepository(this._client);

  final ApiClient _client;

  Future<AuthUser> me() {
    return _client.call(() async {
      final response = await _client.dio.get('/users/me');
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    });
  }

  Future<AuthUser> updateProfile({
    String? firstName,
    String? lastName,
    String? fullName,
    String? phoneNumber,
    String? houseAddress,
    DateTime? dateOfBirth,
    String? profilePhotoUrl,
    bool? twoFactorEnabled,
  }) {
    return _client.call(() async {
      final response = await _client.dio.patch(
        '/users/me',
        data: {
          if (firstName != null) 'firstName': firstName,
          if (lastName != null) 'lastName': lastName,
          if (fullName != null) 'fullName': fullName,
          if (phoneNumber != null) 'phoneNumber': phoneNumber,
          if (houseAddress != null) 'houseAddress': houseAddress,
          if (dateOfBirth != null) 'dateOfBirth': dateOfBirth.toIso8601String(),
          if (profilePhotoUrl != null) 'profilePhotoUrl': profilePhotoUrl,
          if (twoFactorEnabled != null) 'twoFactorEnabled': twoFactorEnabled,
        },
      );
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    });
  }

  /// [accountNumber] and [bankCode] are re-verified against Paystack
  /// server-side, so the [AuthUser] this resolves to carries back whatever
  /// account name Paystack actually resolved — not a client-supplied one.
  Future<AuthUser> updateBankDetails({required String bankCode, required String accountNumber}) {
    return _client.call(() async {
      final response = await _client.dio.patch(
        '/users/me/bank-details',
        data: {'bankCode': bankCode, 'accountNumber': accountNumber},
      );
      return AuthUser.fromJson(response.data as Map<String, dynamic>);
    });
  }
}
