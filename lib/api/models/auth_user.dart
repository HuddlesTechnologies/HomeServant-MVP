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
    this.bankCode,
    this.bankName,
    this.accountNumber,
    this.accountName,
    this.referralCode,
  });

  final String id;
  final String email;
  final UserRole role;
  final String? fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final bool twoFactorEnabled;

  /// The landlord's payout account — the account a tenant's payment is
  /// credited to. Always set as a group, verified against Paystack; see
  /// UsersRepository.updateBankDetails.
  final String? bankCode;
  final String? bankName;
  final String? accountNumber;
  final String? accountName;

  /// This user's own invite code — only present on `GET /users/me` and
  /// `PATCH /users/me` responses, not on login/signup (see backend's
  /// narrower `PublicUser` shape).
  final String? referralCode;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as String,
    email: json['email'] as String,
    role: _roleFromApi(json['role'] as String),
    fullName: json['fullName'] as String?,
    phoneNumber: json['phoneNumber'] as String?,
    profilePhotoUrl: json['profilePhotoUrl'] as String?,
    twoFactorEnabled: json['twoFactorEnabled'] as bool? ?? false,
    bankCode: json['bankCode'] as String?,
    bankName: json['bankName'] as String?,
    accountNumber: json['accountNumber'] as String?,
    accountName: json['accountName'] as String?,
    referralCode: json['referralCode'] as String?,
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
