import 'api_client.dart';

/// One report the signed-in user filed (`GET /reports/mine`).
class MyReport {
  const MyReport({required this.id, required this.status, required this.reason, required this.createdAt, this.subject});

  final String id;

  /// OPEN, IN_PROGRESS or RESOLVED.
  final String status;
  final String reason;
  final DateTime createdAt;

  /// The listing's title or the product's name.
  final String? subject;

  String get statusLabel => switch (status) {
    'IN_PROGRESS' => 'Being reviewed',
    'RESOLVED' => 'Reviewed',
    _ => 'Received',
  };

  factory MyReport.fromApi(Map<String, dynamic> json) => MyReport(
    id: json['id'] as String,
    status: json['status'] as String,
    reason: json['reason'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    subject: (json['property'] as Map<String, dynamic>?)?['title'] as String? ??
        (json['product'] as Map<String, dynamic>?)?['name'] as String?,
  );
}

/// Reporting a listing or a marketplace item to HomeServant's team (backend
/// ReportsController) — the reports land in the admin console's Reports
/// queue.
class ReportsRepository {
  ReportsRepository(this._client);

  final ApiClient _client;

  Future<void> reportProperty(String propertyId, String reason) => _client.call(() async {
    await _client.dio.post('/reports', data: {'targetType': 'PROPERTY', 'propertyId': propertyId, 'reason': reason});
  });

  Future<void> reportProduct(String productId, String reason) => _client.call(() async {
    await _client.dio.post('/reports', data: {'targetType': 'MARKETPLACE_ITEM', 'productId': productId, 'reason': reason});
  });

  Future<List<MyReport>> mine() => _client.call(() async {
    final response = await _client.dio.get('/reports/mine');
    return (response.data as List).cast<Map<String, dynamic>>().map(MyReport.fromApi).toList();
  });
}
