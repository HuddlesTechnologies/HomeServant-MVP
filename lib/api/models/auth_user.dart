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
    this.houseAddress,
    this.dateOfBirth,
    this.mustChangePassword = false,
    this.gender,
    this.occupation,
    this.maritalStatus,
  });

  final String id;
  final String email;
  final UserRole role;
  final String? fullName;
  final String? phoneNumber;
  final String? profilePhotoUrl;
  final bool twoFactorEnabled;

  /// Both only present on `GET /users/me` and `PATCH /users/me` responses,
  /// not on login/signup (see backend's narrower `PublicUser` shape) —
  /// same reasoning as [referralCode] below. AppState.refreshProfile() is
  /// called right after every login/signup flow specifically so these
  /// don't stay stuck at their pre-session-restore defaults.
  final String? houseAddress;
  final DateTime? dateOfBirth;

  /// All optional, added to `PATCH /users/me`/`GET /users/me` alongside
  /// [houseAddress]/[dateOfBirth] — same "only present once the full
  /// profile's been fetched" caveat applies.
  final Gender? gender;
  final String? occupation;
  final MaritalStatus? maritalStatus;

  /// True for an admin account still signed in with the one-time
  /// temporary password from its invite email — the console blocks entry
  /// behind a mandatory password-change step until this clears. Always
  /// false for every other role.
  final bool mustChangePassword;

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

  factory AuthUser.fromApi(Map<String, dynamic> json) => AuthUser(
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
    houseAddress: json['houseAddress'] as String?,
    dateOfBirth: json['dateOfBirth'] != null ? DateTime.parse(json['dateOfBirth'] as String) : null,
    mustChangePassword: json['mustChangePassword'] as bool? ?? false,
    gender: _genderFromApi(json['gender'] as String?),
    occupation: json['occupation'] as String?,
    maritalStatus: _maritalStatusFromApi(json['maritalStatus'] as String?),
  );
}

/// Mirrors the backend's `Gender` enum (`MALE`/`FEMALE`/`OTHER`). Named
/// distinctly from booking.dart's own `TenantGender` (a booking's embedded
/// tenant mirrors the same backend enum) so the two files can evolve
/// independently without an ambiguous-import conflict wherever both end up
/// imported together (e.g. AppState) — see that file's own doc comment.
enum Gender { male, female, other }

Gender? _genderFromApi(String? value) => switch (value) {
  'MALE' => Gender.male,
  'FEMALE' => Gender.female,
  'OTHER' => Gender.other,
  _ => null,
};

extension GenderApi on Gender {
  String get apiValue => switch (this) {
    Gender.male => 'MALE',
    Gender.female => 'FEMALE',
    Gender.other => 'OTHER',
  };

  String get label => switch (this) {
    Gender.male => 'Male',
    Gender.female => 'Female',
    Gender.other => 'Other',
  };
}

/// Mirrors the backend's `MaritalStatus` enum
/// (`SINGLE`/`MARRIED`/`DIVORCED`/`WIDOWED`) — see [Gender]'s doc comment
/// for why this is a distinct type from booking.dart's `TenantMaritalStatus`
/// rather than shared.
enum MaritalStatus { single, married, divorced, widowed }

MaritalStatus? _maritalStatusFromApi(String? value) => switch (value) {
  'SINGLE' => MaritalStatus.single,
  'MARRIED' => MaritalStatus.married,
  'DIVORCED' => MaritalStatus.divorced,
  'WIDOWED' => MaritalStatus.widowed,
  _ => null,
};

extension MaritalStatusApi on MaritalStatus {
  String get apiValue => switch (this) {
    MaritalStatus.single => 'SINGLE',
    MaritalStatus.married => 'MARRIED',
    MaritalStatus.divorced => 'DIVORCED',
    MaritalStatus.widowed => 'WIDOWED',
  };

  String get label => switch (this) {
    MaritalStatus.single => 'Single',
    MaritalStatus.married => 'Married',
    MaritalStatus.divorced => 'Divorced',
    MaritalStatus.widowed => 'Widowed',
  };
}

UserRole _roleFromApi(String value) => switch (value) {
  'LANDLORD' => UserRole.landlord,
  'VENDOR' => UserRole.vendor,
  'ADMIN' => UserRole.admin,
  _ => UserRole.tenant,
};

extension UserRoleApi on UserRole {
  String get apiValue => switch (this) {
    UserRole.landlord => 'LANDLORD',
    UserRole.vendor => 'VENDOR',
    UserRole.admin => 'ADMIN',
    UserRole.tenant => 'TENANT',
  };
}
