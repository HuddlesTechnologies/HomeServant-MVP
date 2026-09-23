import 'api_client.dart';
import 'models/bank.dart';

class ResolvedAccount {
  const ResolvedAccount({required this.accountNumber, required this.accountName});

  final String accountNumber;
  final String accountName;

  factory ResolvedAccount.fromApi(Map<String, dynamic> json) => ResolvedAccount(
    accountNumber: json['accountNumber'] as String,
    accountName: json['accountName'] as String,
  );
}

class PaystackRepository {
  PaystackRepository(this._client);

  final ApiClient _client;

  Future<List<Bank>> listBanks() {
    return _client.call(() async {
      final response = await _client.dio.get('/paystack/banks');
      return (response.data as List).cast<Map<String, dynamic>>().map(Bank.fromApi).toList();
    });
  }

  Future<ResolvedAccount> resolveAccount({required String accountNumber, required String bankCode}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/paystack/resolve-account',
        queryParameters: {'accountNumber': accountNumber, 'bankCode': bankCode},
      );
      return ResolvedAccount.fromApi(response.data as Map<String, dynamic>);
    });
  }
}
