import 'api_client.dart';
import 'models/eviction.dart';

/// Landlord eviction requests and their super-admin review (backend
/// EvictionsController / AdminEvictionsController).
class EvictionsRepository {
  EvictionsRepository(this._client);

  final ApiClient _client;

  List<EvictionRequest> _list(dynamic data) =>
      (data as List).cast<Map<String, dynamic>>().map(EvictionRequest.fromApi).toList();

  Future<List<EvictionRequest>> mine() => _client.call(() async {
    final response = await _client.dio.get('/evictions/mine');
    return _list(response.data);
  });

  Future<EvictionRequest> create(String bookingId, String reason) => _client.call(() async {
    final response = await _client.dio.post('/evictions', data: {'bookingId': bookingId, 'reason': reason});
    return EvictionRequest.fromApi(response.data as Map<String, dynamic>);
  });

  Future<EvictionRequest> cancel(String id) => _client.call(() async {
    final response = await _client.dio.post('/evictions/$id/cancel');
    return EvictionRequest.fromApi(response.data as Map<String, dynamic>);
  });

  Future<EvictionRequest> respond(String id, String response) => _client.call(() async {
    final res = await _client.dio.post('/evictions/$id/respond', data: {'response': response});
    return EvictionRequest.fromApi(res.data as Map<String, dynamic>);
  });

  // --- Super admin ----------------------------------------------------------

  Future<List<EvictionRequest>> adminList({String? status}) => _client.call(() async {
    final response = await _client.dio.get('/admin/evictions', queryParameters: {if (status != null) 'status': status});
    return _list(response.data);
  });

  Future<int> adminPendingCount() => _client.call(() async {
    final response = await _client.dio.get('/admin/evictions/pending-count');
    return (response.data as Map<String, dynamic>)['count'] as int? ?? 0;
  });

  Future<EvictionRequest> review(String id, {required bool approve, String? note}) => _client.call(() async {
    final response = await _client.dio.post(
      '/admin/evictions/$id/review',
      data: {'decision': approve ? 'APPROVE' : 'REJECT', if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    return EvictionRequest.fromApi(response.data as Map<String, dynamic>);
  });
}
