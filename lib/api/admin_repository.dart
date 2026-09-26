import 'api_client.dart';
import 'models/admin_models.dart';
import '../features/dashboard/models/property.dart';

class AdminRepository {
  AdminRepository(this._client);

  final ApiClient _client;

  Future<AdminStats> stats() {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/stats');
      return AdminStats.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<AdminPage<AdminUser>> findUsers({String? role, String? search, int page = 1, bool deactivatedOnly = false}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/admin/users',
        queryParameters: {
          if (role != null) 'role': role,
          if (search != null && search.isNotEmpty) 'search': search,
          if (deactivatedOnly) 'deactivatedOnly': true,
          'page': page,
        },
      );
      return AdminPage<AdminUser>.fromApi(response.data as Map<String, dynamic>, AdminUser.fromApi);
    });
  }

  Future<int> pendingVendorsCount() {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/vendors/pending-count');
      return response.data['count'] as int;
    });
  }

  Future<AdminUserDetail> findUserDetail(String id) {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/users/$id');
      return AdminUserDetail.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Edits basic profile fields — available to every admin tier
  /// (including Support), unlike deactivate/delete which stay
  /// MODERATOR+. Only the fields the caller passes are sent, so a partial
  /// edit doesn't clobber the others.
  Future<void> updateUser(String id, {String? name, String? phone, String? houseAddress}) {
    return _client.call(() async {
      await _client.dio.patch(
        '/admin/users/$id',
        data: {
          if (name != null) 'name': name,
          if (phone != null) 'phone': phone,
          if (houseAddress != null) 'houseAddress': houseAddress,
        },
      );
    });
  }

  Future<void> deactivateUser(String id) {
    return _client.call(() async {
      await _client.dio.patch('/admin/users/$id/deactivate');
    });
  }

  Future<void> deleteUser(String id) {
    return _client.call(() async {
      await _client.dio.delete('/admin/users/$id');
    });
  }

  Future<AdminPage<AdminVendor>> findVendors({String? status, String? search, int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/admin/vendors',
        queryParameters: {if (status != null) 'status': status, if (search != null && search.isNotEmpty) 'search': search, 'page': page},
      );
      return AdminPage<AdminVendor>.fromApi(response.data as Map<String, dynamic>, AdminVendor.fromApi);
    });
  }

  Future<AdminVendorDetail> vendorDetail(String id) {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/vendors/$id');
      return AdminVendorDetail.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<void> approveVendor(String id) {
    return _client.call(() async {
      await _client.dio.patch('/admin/vendors/$id/approve');
    });
  }

  Future<void> rejectVendor(String id, {String? reason}) {
    return _client.call(() async {
      await _client.dio.patch('/admin/vendors/$id/reject', data: {if (reason != null && reason.isNotEmpty) 'reason': reason});
    });
  }

  /// [reason] is required — it's emailed to the vendor, same as
  /// [removeProperty]/[removeProduct]'s delist reason.
  Future<void> suspendVendor(String id, {required String reason}) {
    return _client.call(() async {
      await _client.dio.patch('/admin/vendors/$id/suspend', data: {'reason': reason});
    });
  }

  Future<void> unsuspendVendor(String id, {required String reason}) {
    return _client.call(() async {
      await _client.dio.patch('/admin/vendors/$id/unsuspend', data: {'reason': reason});
    });
  }

  Future<AdminPage<AdminProperty>> findProperties({String? search, int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/admin/properties',
        queryParameters: {if (search != null && search.isNotEmpty) 'search': search, 'page': page},
      );
      return AdminPage<AdminProperty>.fromApi(response.data as Map<String, dynamic>, AdminProperty.fromApi);
    });
  }

  /// Full listing detail — reuses [Property.fromApi] since the admin
  /// endpoint returns the same shape `GET /properties/:id` does (the raw
  /// row plus the landlord relation), just without the aggregated
  /// rating/review fields (which [Property.fromApi] already defaults).
  Future<Property> propertyDetail(String id) {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/properties/$id');
      return Property.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<void> removeProperty(String id, {required String reason}) {
    return _client.call(() async {
      await _client.dio.delete('/admin/properties/$id', data: {'reason': reason});
    });
  }

  /// Moderator/super-admin override for the landlord-side "can't re-list
  /// an occupied property" rule. Not yet confirmed against a real backend
  /// route as of this writing — this is the reasonably-named endpoint this
  /// action expects; confirm/add it server-side if it 404s.
  Future<void> relistProperty(String id) {
    return _client.call(() async {
      await _client.dio.patch('/admin/properties/$id/relist');
    });
  }

  Future<AdminPage<AdminProduct>> findProducts({String? search, int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/admin/marketplace/products',
        queryParameters: {if (search != null && search.isNotEmpty) 'search': search, 'page': page},
      );
      return AdminPage<AdminProduct>.fromApi(response.data as Map<String, dynamic>, AdminProduct.fromApi);
    });
  }

  Future<void> removeProduct(String id, {required String reason}) {
    return _client.call(() async {
      await _client.dio.delete('/admin/marketplace/products/$id', data: {'reason': reason});
    });
  }

  Future<AdminPage<AdminOrder>> findOrders({int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/marketplace/orders', queryParameters: {'page': page});
      return AdminPage<AdminOrder>.fromApi(response.data as Map<String, dynamic>, AdminOrder.fromApi);
    });
  }

  /// The current admin's own level — fetched right after admin login to
  /// decide what the console shows/allows (the server enforces the real
  /// authorization on every write regardless, this is only for the UI).
  Future<AdminLevel> myLevel() {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/me');
      return AdminLevel.fromApi((response.data as Map<String, dynamic>)['adminLevel'] as String);
    });
  }

  Future<List<AdminAccount>> findAdmins() {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/admins');
      return (response.data as List).cast<Map<String, dynamic>>().map(AdminAccount.fromApi).toList();
    });
  }

  /// Step 1 of the invite flow — sends a confirmation code and one-time
  /// temporary password to [email] in a single email. Call [confirmAdmin]
  /// with that code to actually create the account.
  Future<void> requestAdmin({required String email, required String fullName, required AdminLevel level}) {
    return _client.call(() async {
      await _client.dio.post(
        '/admin/admins/request',
        data: {'email': email, 'fullName': fullName, 'level': level.apiValue},
      );
    });
  }

  Future<void> confirmAdmin({required String email, required String code}) {
    return _client.call(() async {
      await _client.dio.post('/admin/admins/confirm', data: {'email': email, 'code': code});
    });
  }

  Future<void> setAdminLevel(String id, AdminLevel level) {
    return _client.call(() async {
      await _client.dio.patch('/admin/admins/$id/level', data: {'level': level.apiValue});
    });
  }

  Future<void> setAdminTwoFactor(String id, bool enabled) {
    return _client.call(() async {
      await _client.dio.patch('/admin/admins/$id/two-factor', data: {'enabled': enabled});
    });
  }

  /// Step-up flow for a locked-out admin's password — the OTP goes to
  /// *this* (acting) admin's own email, not the target's. See
  /// AdminService.requestAdminPasswordReset.
  Future<void> requestAdminPasswordReset(String id) {
    return _client.call(() async {
      await _client.dio.post('/admin/admins/$id/reset-password/request');
    });
  }

  Future<void> confirmAdminPasswordReset(String id, String code) {
    return _client.call(() async {
      await _client.dio.post('/admin/admins/$id/reset-password/confirm', data: {'code': code});
    });
  }

  Future<void> removeAdmin(String id) {
    return _client.call(() async {
      await _client.dio.delete('/admin/admins/$id');
    });
  }

  Future<AdminPage<ActivityLogEntry>> findActivityLog({int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/activity-log', queryParameters: {'page': page});
      return AdminPage<ActivityLogEntry>.fromApi(response.data as Map<String, dynamic>, ActivityLogEntry.fromApi);
    });
  }

  /// SUPER_ADMIN only — the backend independently re-checks this.
  Future<void> clearActivityLog() {
    return _client.call(() async {
      await _client.dio.delete('/admin/activity-log');
    });
  }

  Future<AdminPage<AdminReport>> findReports({ReportStatus? status, int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/reports',
        queryParameters: {if (status != null) 'status': status.apiValue, 'page': page},
      );
      return AdminPage<AdminReport>.fromApi(response.data as Map<String, dynamic>, AdminReport.fromApi);
    });
  }

  Future<int> openReportsCount() {
    return _client.call(() async {
      final response = await _client.dio.get('/reports/open-count');
      return (response.data as Map<String, dynamic>)['count'] as int;
    });
  }

  Future<void> setReportStatus(String id, ReportStatus status) {
    return _client.call(() async {
      await _client.dio.patch('/reports/$id/status', data: {'status': status.apiValue});
    });
  }

  Future<void> transferReport(String id, String adminId) {
    return _client.call(() async {
      await _client.dio.patch('/reports/$id/transfer', data: {'adminId': adminId});
    });
  }
}
