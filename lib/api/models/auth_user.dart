import '../../models/user_role.dart';

/// Mirrors the backend's `PublicUser` shape (see
/// backend/src/auth/auth.service.ts) — what comes back from
/// signup/login/verify/`GET /users/me`.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.role,
    this.fullName,
    this.phoneNumber,
    this.profilePhotoUrl,
    this.twoFactorEnabled = false,
  });

  final String id;
  final String email;
  final UserRole role;
  final String? fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final bool twoFactorEnabled;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    role: _roleFromApi(json['role'] as String),
    fullName: json['fullName'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
    twoFactorEnabled: json['twoFactorEnabled'] as bool? ?? false,
  );
}

UserRole _roleFromApi(String value) => switch (value) {
  'LANDLORD' => UserRole.landlord,
  'VENDOR' => UserRole.vendor,
  _ => UserRole.tenant,
};

extension UserRoleApi on UserRole {
  String get apiValue => switch (this) {
    UserRole.landlord => 'LANDLORD',
    UserRole.vendor => 'VENDOR',
    UserRole.tenant => 'TENANT',
  };
}
