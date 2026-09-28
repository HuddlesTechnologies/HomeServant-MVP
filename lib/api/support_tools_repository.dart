import 'api_client.dart';
import 'models/support_tools.dart';

/// Admin-only support tools (backend SupportToolsController): internal
/// notes, triage, customer context, saved replies and hand-off targets.
class SupportToolsRepository {
  SupportToolsRepository(this._client);

  final ApiClient _client;

  Future<List<SupportNote>> notes(String threadId) => _client.call(() async {
    final response = await _client.dio.get('/threads/$threadId/notes');
    return (response.data as List).cast<Map<String, dynamic>>().map(SupportNote.fromApi).toList();
  });

  Future<SupportNote> addNote(String threadId, String body) => _client.call(() async {
    final response = await _client.dio.post('/threads/$threadId/notes', data: {'body': body});
    return SupportNote.fromApi(response.data as Map<String, dynamic>);
  });

  Future<void> triage(String threadId, {SupportTopic? topic, SupportPriority? priority}) => _client.call(() async {
    await _client.dio.patch(
      '/threads/$threadId/triage',
      data: {if (topic != null) 'topic': topic.apiValue, if (priority != null) 'priority': priority.apiValue},
    );
  });

  /// Records a call to the customer with [reason] (required, kept with the
  /// chat) and returns the number to dial.
  Future<({String phoneNumber, String? customerName})> logCall(String threadId, String reason) => _client.call(() async {
    final response = await _client.dio.post('/threads/$threadId/calls', data: {'reason': reason});
    final data = response.data as Map<String, dynamic>;
    return (phoneNumber: data['phoneNumber'] as String, customerName: data['customerName'] as String?);
  });

  /// Every call placed from this chat, newest first.
  Future<List<SupportCall>> calls(String threadId) => _client.call(() async {
    final response = await _client.dio.get('/threads/$threadId/calls');
    return (response.data as List).cast<Map<String, dynamic>>().map(SupportCall.fromApi).toList();
  });

  Future<CustomerContext> customerContext(String threadId) => _client.call(() async {
    final response = await _client.dio.get('/threads/$threadId/customer-context');
    return CustomerContext.fromApi(response.data as Map<String, dynamic>);
  });

  Future<List<SavedReply>> savedReplies() => _client.call(() async {
    final response = await _client.dio.get('/support/saved-replies');
    return (response.data as List).cast<Map<String, dynamic>>().map(SavedReply.fromApi).toList();
  });

  Future<SavedReply> createSavedReply(String title, String body) => _client.call(() async {
    final response = await _client.dio.post('/support/saved-replies', data: {'title': title, 'body': body});
    return SavedReply.fromApi(response.data as Map<String, dynamic>);
  });

  Future<SavedReply> updateSavedReply(String id, String title, String body) => _client.call(() async {
    final response = await _client.dio.patch('/support/saved-replies/$id', data: {'title': title, 'body': body});
    return SavedReply.fromApi(response.data as Map<String, dynamic>);
  });

  Future<void> deleteSavedReply(String id) => _client.call(() async {
    await _client.dio.delete('/support/saved-replies/$id');
  });

  Future<List<TransferTarget>> transferTargets() => _client.call(() async {
    final response = await _client.dio.get('/support/admins');
    return (response.data as List).cast<Map<String, dynamic>>().map(TransferTarget.fromApi).toList();
  });

  /// Super admins only — the support dashboard for the last [days] days.
  Future<SupportMetrics> metrics(int days) => _client.call(() async {
    final response = await _client.dio.get('/support/metrics', queryParameters: {'days': days});
    return SupportMetrics(response.data as Map<String, dynamic>);
  });
}
