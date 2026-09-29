import '../../models/user_role.dart';
import 'verification.dart';

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
    this.verificationStatus,
    this.verificationNote,
    this.listingsHiddenUntilVerified = false,
    this.houseAddress,
    this.dateOfBirth,
    this.mustChangePassword = false,
    this.gender,
    this.occupation,
    this.maritalStatus,
    this.bio,
    this.hobbies = const [],
    this.hasFullProfile = false,
    this.profileCompleted = true,
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

  /// Booking profile — background and hobbies a landlord reads with a
  /// booking request (full profile shape only).
  final String? bio;
  final List<String> hobbies;

  /// True for a `GET /users/me`/`PATCH /users/me`/`PATCH /users/me/bank-
  /// details` response (all select the full `profileSelect` shape, always
  /// including a `houseAddress` key even when its value is null) — false
  /// for the narrower login/signup/2FA/Google-auth response, which omits
  /// the key entirely. Lets [AppState._applyUser] tell "not fetched yet"
  /// (narrow response, null means unknown) apart from "actually cleared"
  /// (full response, null means the field was genuinely unset/blanked) —
  /// without this, a field intentionally cleared via [AppState.
  /// completeProfile] (e.g. blanking a phone number) would come back null
  /// from the server but never actually apply locally, since the old
  /// non-null value would otherwise win by default.
  final bool hasFullProfile;

  /// Server-owned "has finished the signup wizard" latch (backend
  /// `User.profileCompletedAt`) — present on every response shape,
  /// including the narrow login/signup/2FA/Google one, so it's known the
  /// instant a session starts rather than after a follow-up profile fetch.
  /// The router's profile-completion redirect keys off this alone. Treated
  /// as true when the key is missing entirely (a backend that predates
  /// the field), so a real account is never trapped in the wizard.
  final bool profileCompleted;

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

  /// This user's identity verification (null when not submitted, or on the
  /// narrower login response) and, when rejected, what to fix.
  final VerificationStatus? verificationStatus;
  final String? verificationNote;

  /// Landlord only: Platform Controls is hiding this landlord's listings
  /// from tenants until their identity is verified.
  final bool listingsHiddenUntilVerified;

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
    verificationStatus: VerificationStatus.fromApi((json['identityVerification'] as Map<String, dynamic>?)?['status'] as String?),
    verificationNote: (json['identityVerification'] as Map<String, dynamic>?)?['reviewNote'] as String?,
    listingsHiddenUntilVerified: json['listingsHiddenUntilVerified'] as bool? ?? false,
    houseAddress: json['houseAddress'] as String?,
    dateOfBirth: json['dateOfBirth'] != null ? DateTime.parse(json['dateOfBirth'] as String) : null,
    mustChangePassword: json['mustChangePassword'] as bool? ?? false,
    gender: _genderFromApi(json['gender'] as String?),
    occupation: json['occupation'] as String?,
    maritalStatus: _maritalStatusFromApi(json['maritalStatus'] as String?),
    bio: json['bio'] as String?,
    hobbies: (json['hobbies'] as List?)?.cast<String>() ?? const [],
    hasFullProfile: json.containsKey('houseAddress'),
    profileCompleted: !json.containsKey('profileCompletedAt') || json['profileCompletedAt'] != null,
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
