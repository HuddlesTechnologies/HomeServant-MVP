import 'api_client.dart';
import 'models/admin_models.dart';

class AdminRepository {
  AdminRepository(this._client);

  final ApiClient _client;

  Future<AdminStats> stats() {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/stats');
      return AdminStats.fromApi(response.data as Map<String, dynamic>);
    });
  }

  Future<AdminPage<AdminUser>> findUsers({String? role, String? search, int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/admin/users',
        queryParameters: {if (role != null) 'role': role, if (search != null && search.isNotEmpty) 'search': search, 'page': page},
      );
      final data = response.data as Map<String, dynamic>;
      return AdminPage<AdminUser>(
        items: (data['items'] as List).cast<Map<String, dynamic>>().map(AdminUser.fromApi).toList(),
        total: data['total'] as int,
        page: data['page'] as int,
        pageSize: data['pageSize'] as int,
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
      final data = response.data as Map<String, dynamic>;
      return AdminPage<AdminVendor>(
        items: (data['items'] as List).cast<Map<String, dynamic>>().map(AdminVendor.fromApi).toList(),
        total: data['total'] as int,
        page: data['page'] as int,
        pageSize: data['pageSize'] as int,
      );
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

  Future<void> suspendVendor(String id) {
    return _client.call(() async {
      await _client.dio.patch('/admin/vendors/$id/suspend');
    });
  }

  Future<void> unsuspendVendor(String id) {
    return _client.call(() async {
      await _client.dio.patch('/admin/vendors/$id/unsuspend');
    });
  }

  Future<AdminPage<AdminProperty>> findProperties({String? search, int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/admin/properties',
        queryParameters: {if (search != null && search.isNotEmpty) 'search': search, 'page': page},
      );
      final data = response.data as Map<String, dynamic>;
      return AdminPage<AdminProperty>(
        items: (data['items'] as List).cast<Map<String, dynamic>>().map(AdminProperty.fromApi).toList(),
        total: data['total'] as int,
        page: data['page'] as int,
        pageSize: data['pageSize'] as int,
      );
    });
  }

  Future<void> removeProperty(String id) {
    return _client.call(() async {
      await _client.dio.delete('/admin/properties/$id');
    });
  }

  Future<AdminPage<AdminProduct>> findProducts({String? search, int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get(
        '/admin/marketplace/products',
        queryParameters: {if (search != null && search.isNotEmpty) 'search': search, 'page': page},
      );
      final data = response.data as Map<String, dynamic>;
      return AdminPage<AdminProduct>(
        items: (data['items'] as List).cast<Map<String, dynamic>>().map(AdminProduct.fromApi).toList(),
        total: data['total'] as int,
        page: data['page'] as int,
        pageSize: data['pageSize'] as int,
      );
    });
  }

  Future<void> removeProduct(String id) {
    return _client.call(() async {
      await _client.dio.delete('/admin/marketplace/products/$id');
    });
  }

  Future<AdminPage<AdminOrder>> findOrders({int page = 1}) {
    return _client.call(() async {
      final response = await _client.dio.get('/admin/marketplace/orders', queryParameters: {'page': page});
      final data = response.data as Map<String, dynamic>;
      return AdminPage<AdminOrder>(
        items: (data['items'] as List).cast<Map<String, dynamic>>().map(AdminOrder.fromApi).toList(),
        total: data['total'] as int,
        page: data['page'] as int,
        pageSize: data['pageSize'] as int,
      );
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
}
