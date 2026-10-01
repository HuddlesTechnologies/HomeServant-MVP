import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/admin_repository.dart';
import '../api/models/admin_models.dart';
import '../api/api_client.dart';
import '../api/auth_repository.dart';
import '../api/bookings_repository.dart';
import '../api/chat_repository.dart';
export '../api/bookings_repository.dart' show PaymentInitiation, BookingCreationResult, RenewalQuote;
import '../api/favorites_repository.dart';
import '../api/marketplace_orders_repository.dart';
import '../api/marketplace_products_repository.dart';
import '../api/models/app_notification.dart';
import '../api/models/auth_user.dart';
import '../api/models/booking.dart';
import '../api/notifications_repository.dart';
import '../api/paystack_repository.dart';
import '../api/properties_repository.dart';
import '../api/evictions_repository.dart';
import '../api/models/eviction.dart';
import '../api/push_repository.dart';
import '../api/verification_repository.dart';
import '../api/reports_repository.dart';
import '../api/models/verification.dart';
import '../services/browser_notifications.dart';
import '../api/support_tools_repository.dart';
import '../api/reviews_repository.dart';
import '../api/token_storage.dart';
import '../core/payment_return_stub.dart' if (dart.library.html) '../core/payment_return_web.dart';
import '../api/web_session_storage_stub.dart' if (dart.library.html) '../api/web_session_storage_web.dart' as web_storage;
import '../api/uploads_repository.dart';
import '../api/users_repository.dart';
import '../api/vendors_repository.dart';
import '../api/models/tenancy_agreement.dart';
import '../features/dashboard/models/property.dart';
import '../models/dashboard_theme.dart';
import '../models/user_role.dart';
import '../services/app_icon_service.dart';
import '../services/chat_socket_service.dart';
import '../services/google_auth_service.dart';

part 'sections/notifications_section.dart';
part 'sections/listings_section.dart';
part 'sections/bookings_section.dart';
part 'sections/device_preferences_section.dart';

/// What happened on a [AppState.login]/[AppState.loginWithGoogle] call —
/// see each method's doc comment for how a caller should react to
/// [requiresTwoFactor]/[requiresReactivation].
enum LoginOutcome { success, requiresTwoFactor, requiresReactivation, requiresEmailVerification }

/// Owns the app's session (real, backed by the HomeServant API) plus a
/// handful of device-local preferences (theme, notification toggles, app
/// lock) that have no server home. Session data is never persisted to
/// [SharedPreferences] — the access/refresh tokens and the app-lock PIN
/// live in the platform keychain instead (see [TokenStorage]); everything
/// else about the signed-in user is re-fetched from the API on launch via
/// [load].
class AppState extends ChangeNotifier with _NotificationsSection, _ListingsSection, _BookingsSection, _DevicePreferencesSection {
  AppState() {
    _apiClient = ApiClient(_tokens)..onSessionExpired = _handleSessionExpired;
    _authRepo = AuthRepository(_apiClient, _tokens);
    _usersRepo = UsersRepository(_apiClient);
    _propertiesRepo = PropertiesRepository(_apiClient);
    _bookingsRepo = BookingsRepository(_apiClient);
    _favoritesRepo = FavoritesRepository(_apiClient);
    _reviewsRepo = ReviewsRepository(_apiClient);
    _chatRepo = ChatRepository(_apiClient);
    _supportToolsRepo = SupportToolsRepository(_apiClient);
    _pushRepo = PushRepository(_apiClient);
    _evictionsRepo = EvictionsRepository(_apiClient);
    _verificationRepo = VerificationRepository(_apiClient);
    _reportsRepo = ReportsRepository(_apiClient);
    _uploadsRepo = UploadsRepository(_apiClient);
    _vendorsRepo = VendorsRepository(_apiClient);
    _marketplaceProductsRepo = MarketplaceProductsRepository(_apiClient);
    _marketplaceOrdersRepo = MarketplaceOrdersRepository(_apiClient);
    _paystackRepo = PaystackRepository(_apiClient);
    _notificationsRepo = NotificationsRepository(_apiClient);
    _adminRepo = AdminRepository(_apiClient);
    // Keeps the bookings lists (landlord/tenant) live instead of only ever
    // being fetched once at login — every booking mutation (a new request,
    // an accept/decline, an inspection date, a payment) already passes
    // through NotificationsService.create on the backend, which is also
    // what NotificationBannerOverlay's toast reuses, so this piggybacks on
    // the same `notification:new` socket event rather than needing a
    // separate push channel. Subscribed once, for the app's whole
    // lifetime — _chatSocket itself is a single long-lived instance that
    // reconnects under the hood across login/logout, so this stays valid
    // the same way NotificationBannerOverlay's own subscription does.
    _chatSocket.onNotification.listen(_handleRealtimeNotification);
    // Someone else rented (or the landlord edited/hid) a listing: refresh
    // what a tenant is browsing, quietly, so it just drops off the list.
    _chatSocket.onListingsChanged.listen((_) {
      if (role == UserRole.tenant) unawaited(loadProperties(silent: true).catchError((_) {}));
    });
    _chatSocket.onAccountBanned.listen(
      (reason) => _handleSessionExpired(
        'This account has been permanently banned from HomeServant.'
        '${reason?.trim().isNotEmpty == true ? ' Reason: ${reason!.trim()}' : ''} '
        'If you believe this is a mistake, contact HomeServant support.',
      ),
    );
    _chatRepo.onLocalChange = _chatSocket.notifyThreadsChanged;
    _chatRepo.onThreadRead = _markThreadNotificationsReadLocally;
    // Notifications created while the socket was down never arrived live.
    _chatSocket.onReconnected.listen((_) {
      // Anything that changed while the socket was down (phone locked, tab
      // in the background, flaky network) never arrived live — fetch it all.
      if (userId != null) unawaited(refreshAll());
    });
  }

  static const _prefsKey = 'app_state_v2';

  @override
  final TokenStorage _tokens = TokenStorage();
  late final ApiClient _apiClient;
  late final AuthRepository _authRepo;
  late final UsersRepository _usersRepo;
  @override
  late final PropertiesRepository _propertiesRepo;
  @override
  late final BookingsRepository _bookingsRepo;
  @override
  late final FavoritesRepository _favoritesRepo;
  @override
  late final ReviewsRepository _reviewsRepo;
  late final ChatRepository _chatRepo;
  late final SupportToolsRepository _supportToolsRepo;
  @override
  late final PushRepository _pushRepo;
  @override
  late final EvictionsRepository _evictionsRepo;
  late final VerificationRepository _verificationRepo;
  late final ReportsRepository _reportsRepo;
  late final UploadsRepository _uploadsRepo;
  late final VendorsRepository _vendorsRepo;
  late final MarketplaceProductsRepository _marketplaceProductsRepo;
  late final MarketplaceOrdersRepository _marketplaceOrdersRepo;
  late final PaystackRepository _paystackRepo;
  @override
  late final NotificationsRepository _notificationsRepo;
  late final AdminRepository _adminRepo;

  /// Per-thread chat, file uploads, and the whole marketplace surface are
  /// screen-local concerns (each screen manages its own fetch/paginate) —
  /// exposed directly rather than mirrored into AppState's own fields.
  ChatRepository get chat => _chatRepo;
  SupportToolsRepository get supportTools => _supportToolsRepo;
  UploadsRepository get uploads => _uploadsRepo;
  VendorsRepository get vendors => _vendorsRepo;
  MarketplaceProductsRepository get marketplaceProducts => _marketplaceProductsRepo;
  MarketplaceOrdersRepository get marketplaceOrders => _marketplaceOrdersRepo;
  PaystackRepository get paystack => _paystackRepo;
  AdminRepository get admin => _adminRepo;
  EvictionsRepository get evictionsRepo => _evictionsRepo;
  VerificationRepository get verification => _verificationRepo;

  /// Reporting a listing or marketplace item, and the user's own reports.
  ReportsRepository get reports => _reportsRepo;

  /// Listing calls not covered by the cached lists (e.g. featured ads).
  PropertiesRepository get listings => _propertiesRepo;

  /// True once [load] has finished restoring (or found nothing to restore).
  /// AppLockGate waits for this before deciding whether a cold start should
  /// open locked, so it reads the setting as it was *before* this launch —
  /// not a value flipped live during the current session (see [load]).
  bool isLoaded = false;

  // --- Session -------------------------------------------------------------

  /// Null until signup/login/OTP-verify succeeds or a saved session is
  /// restored on launch — see [isAuthenticated].
  @override
  String? userId;
  bool get isAuthenticated => userId != null;

  /// True right after a refresh-token failure (the session genuinely
  /// expired, not just an access token due for renewal) clears local
  /// session state — SessionExpiredGate watches this to show an explicit
  /// "you were signed out" modal instead of silently dropping the user
  /// back to a login screen with no explanation. Cleared by
  /// [acknowledgeSessionExpired] once the user's seen it. Never set by a
  /// deliberate [logout] — only by [_handleSessionExpired].
  bool sessionExpired = false;

  /// Set together with [sessionExpired] when the session ended because the
  /// account was permanently banned: the server's explanation, with the
  /// reason. SessionExpiredGate shows it instead of "session expired".
  String? bannedMessage;

  void acknowledgeSessionExpired() {
    sessionExpired = false;
    bannedMessage = null;
    notifyListeners();
  }

  void _handleSessionExpired([String? banned]) {
    sessionExpired = true;
    bannedMessage = banned;
    // Clear the stored tokens now, like every other sign-out: the server
    // already rejects them, so keeping them would only leave dead
    // credentials on the device.
    unawaited(_tokens.clear());
    unawaited(GoogleAuthService.signOut());
    _clearSession();
  }

  UserRole role = UserRole.tenant;
  String email = '';
  String fullName = '';
  String phoneNumber = '';
  String houseAddress = '';
  DateTime? dateOfBirth;
  Gender? gender;
  String? occupation;

  /// Booking profile (see AuthUser.bio/hobbies).
  String? bio;
  List<String> hobbies = const [];
  MaritalStatus? maritalStatus;

  /// True for an admin still signed in with the one-time temp password
  /// from their invite email — see AuthUser.mustChangePassword.
  bool mustChangePassword = false;

  /// Whether this tenant/landlord has ever finished the signup wizard —
  /// see AuthUser.profileCompleted. The single source of truth for the
  /// router's "finish setting up your account" redirect.
  bool profileCompleted = true;

  /// This user's own invite code, shown on "Invite Friends" — always
  /// real, from the server (see [_applyUser]); the backend assigns one
  /// lazily on first `GET /users/me` if an account predates this field.
  String myReferralCode = '';

  /// This account's identity verification (see VerificationService); null
  /// when nothing was submitted. [verificationNote] says what to fix when
  /// rejected.
  VerificationStatus? verificationStatus;
  String? verificationNote;
  bool listingsHiddenUntilVerified = false;

  /// A local file path/blob URL while a freshly-picked photo hasn't been
  /// uploaded yet, or the persisted `https://` URL once it has — see
  /// [imageProviderForPath], which renders either.
  String? profilePhotoPath;
  bool twoFactorEnabled = false;

  /// The landlord's payout account — the account a tenant's payment is
  /// credited to. Populated from the server (see [_applyUser]); never set
  /// directly from user input, since [accountName] is only ever trusted
  /// once Paystack has resolved it (see [updateBankDetails]).
  String? bankCode;
  String? bankName;
  String? accountNumber;
  String? accountName;

  void selectRole(UserRole newRole) {
    role = newRole;
    notifyListeners();
  }

  void setEmail(String value) {
    email = value;
    notifyListeners();
  }

  /// Stages fields collected before an account exists yet (mid-signup) —
  /// name/phone/houseAddress are re-sent to the server via
  /// [completeProfile] once the account does exist.
  void setProfileBasics({required String name, required String phone, String? houseAddress}) {
    fullName = name;
    phoneNumber = phone;
    if (houseAddress != null) this.houseAddress = houseAddress;
    notifyListeners();
  }

  // --- Auth ------------------------------------------------------------

  Future<void> signup({required String email, required String password, String? fullName}) async {
    await _authRepo.signup(email: email, password: password, role: role, fullName: fullName);
    this.email = email;
    notifyListeners();
  }

  /// Shared tail end of every flow that ends in a freshly-authenticated
  /// session (signup verification, login, Google sign-in, 2FA
  /// verification) — applies the narrow auth response, then fetches the
  /// full profile and initial app data. Kept as one helper (rather than
  /// copy-pasted per call site) specifically so this ordering can't drift
  /// between call sites — a version of this exact sequence firing
  /// notifyListeners() (inside [_applyUser]) before [refreshProfile]
  /// resolves was the root cause of a router race that stranded returning
  /// users on a dead-end profile-completion screen every login.
  Future<void> _completeAuthentication(AuthUser user) async {
    _applyUser(user);
    await refreshProfile();
    await _loadInitialData();
  }

  Future<void> verifySignupOtp(String code) async {
    final user = await _authRepo.verifySignup(email: email, code: code);
    await _completeAuthentication(user);
  }

  /// [requiresReactivation]: the account is deactivated — show a confirm
  /// prompt, then call this again with the same [email]/[password] and
  /// `reactivate: true` to actually complete the login (see
  /// AuthRepository.login). [requiresTwoFactor]: route to an OTP screen
  /// and call [verifyLoginTwoFactor] next — [email] is already set either
  /// way. [requiresEmailVerification]: the account never entered its
  /// signup code; a new one was just emailed — route to the signup-code
  /// screen and call [verifySignupOtp].
  Future<LoginOutcome> login({
    required String email,
    required String password,
    bool reactivate = false,
    String portal = 'APP',
  }) async {
    final result = await _authRepo.login(
      email: email,
      password: password,
      reactivate: reactivate,
      portal: portal,
    );
    this.email = email;
    if (result.requiresEmailVerification) {
      notifyListeners();
      return LoginOutcome.requiresEmailVerification;
    }
    if (result.requiresReactivation) {
      notifyListeners();
      return LoginOutcome.requiresReactivation;
    }
    if (result.requiresTwoFactor) {
      notifyListeners();
      return LoginOutcome.requiresTwoFactor;
    }
    await _completeAuthentication(result.user!);
    return LoginOutcome.success;
  }

  /// The Google ID token from the most recent sign-in, kept only so a
  /// [LoginOutcome.requiresReactivation] retry (`reactivate: true`) can
  /// reuse it instead of re-triggering the native picker — Google ID
  /// tokens stay valid for reuse within a short window after sign-in.
  String? _pendingGoogleIdToken;

  /// `null` if the user closed the Google picker/popup without choosing
  /// an account. [role] only matters the first time this Google account
  /// is used — see [AuthRepository.googleAuth]. On [reactivate], reuses
  /// the ID token from the immediately preceding call rather than
  /// prompting the picker again.
  ///
  /// [idToken] is passed in on web, where Google's rendered button has
  /// already produced one (see GoogleAuthService); on mobile it's omitted
  /// and the native picker is opened here instead.
  /// [role] is the sign-in/sign-up page's role (defaults to [role] state):
  /// a new account gets it, and an existing account of another role is refused.
  Future<LoginOutcome?> loginWithGoogle({String? idToken, bool reactivate = false, UserRole? role}) async {
    idToken = reactivate ? _pendingGoogleIdToken : (idToken ?? await GoogleAuthService.signInAndGetIdToken());
    if (idToken == null) return null;
    _pendingGoogleIdToken = idToken;
    final result = await _authRepo.googleAuth(idToken: idToken, role: role ?? this.role, reactivate: reactivate);
    if (result.requiresReactivation) {
      notifyListeners();
      return LoginOutcome.requiresReactivation;
    }
    _pendingGoogleIdToken = null;
    await _completeAuthentication(result.user!);
    return LoginOutcome.success;
  }

  Future<void> verifyLoginTwoFactor(String code) async {
    final user = await _authRepo.verifyLoginTwoFactor(email: email, code: code);
    await _completeAuthentication(user);
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    await _authRepo.changePassword(currentPassword: currentPassword, newPassword: newPassword);
    // Clears mustChangePassword locally right away — otherwise it'd stay
    // stuck true (and the admin console's forced change-password gate
    // stuck up) until something else happened to refetch the profile.
    await refreshProfile();
  }

  /// [purpose] is `'SIGNUP'` or `'LOGIN_2FA'` — see AuthService.resendOtp.
  /// Always resolves the same way regardless of whether [email] is
  /// actually eligible for a new code right now.
  Future<void> resendOtp({required String purpose}) {
    return _authRepo.resendOtp(email: email, purpose: purpose);
  }

  /// Always succeeds from the caller's point of view regardless of
  /// whether [email] has an account — see AuthService.forgotPassword on
  /// the backend for why.
  Future<void> forgotPassword(String email) {
    return _authRepo.forgotPassword(email: email);
  }

  Future<void> resetPassword({required String email, required String code, required String newPassword}) {
    return _authRepo.resetPassword(email: email, code: code, newPassword: newPassword);
  }

  Future<void> completeProfile({
    String? fullName,
    String? phoneNumber,
    String? houseAddress,
    DateTime? dateOfBirth,
    String? profilePhotoUrl,
    String? referralCode,
    Gender? gender,
    String? occupation,
    MaritalStatus? maritalStatus,
    String? bio,
    List<String>? hobbies,
  }) async {
    final user = await _usersRepo.updateProfile(
      bio: bio,
      hobbies: hobbies,
      fullName: fullName,
      phoneNumber: phoneNumber,
      houseAddress: houseAddress,
      dateOfBirth: dateOfBirth,
      profilePhotoUrl: profilePhotoUrl,
      referralCode: referralCode,
      gender: gender,
      occupation: occupation,
      maritalStatus: maritalStatus,
    );
    _applyUser(user);
    notifyListeners();
  }

  /// Re-fetches this user's own profile from the server — used where a
  /// field populated by [_applyUser] (e.g. [myReferralCode]) might not be
  /// loaded yet and there's no more specific update call to make instead.
  Future<void> refreshProfile() async {
    final user = await _usersRepo.me();
    _applyUser(user);
  }

  Future<void> setTwoFactorEnabled(bool value) async {
    final user = await _usersRepo.updateProfile(twoFactorEnabled: value);
    _applyUser(user);
  }

  Future<void> updateBankDetails({required String bankCode, required String accountNumber}) async {
    final user = await _usersRepo.updateBankDetails(bankCode: bankCode, accountNumber: accountNumber);
    _applyUser(user);
  }

  Future<void> logout() async {
    // Stop this browser receiving the signed-out user's push notifications
    // (the next person to use it would otherwise get them). Needs the
    // session, so it runs before the server logout.
    await _forgetWebPush();
    try {
      await _authRepo.logout();
    } finally {
      // Local session state must always be torn down, even if the
      // repo/server call throws — otherwise userId stays set and the login
      // button just walks the user back into their still-"authenticated"
      // session without re-entering any credentials.
      //
      // Awaited (unlike the other forced-sign-out paths) so a same-browser
      // "Login with Google" retry right after this can't silently reuse
      // the plugin's still-cached account.
      await GoogleAuthService.signOut();
      _clearSession();
    }
  }

  /// Hides this landlord's listings and signs out every session
  /// server-side; the account reactivates itself automatically the next
  /// time it logs in successfully (see AuthService.issueTokens).
  Future<void> deactivateAccount() async {
    await _authRepo.deactivate();
    await _tokens.clear();
    unawaited(GoogleAuthService.signOut());
    _clearSession();
  }

  /// Permanently deletes the account and everything tied to it
  /// server-side — unlike [logout]/[deactivateAccount], there is no
  /// undo.
  Future<void> deleteAccount() async {
    await _authRepo.deleteAccount();
    await _tokens.clear();
    unawaited(GoogleAuthService.signOut());
    _clearSession();
  }

  void _applyUser(AuthUser user) {
    userId = user.id;
    email = user.email;
    role = user.role;
    // Each field applies when the incoming value is non-null (the normal
    // case), OR when this is confirmed to be a full-profile response (see
    // AuthUser.hasFullProfile) — in which case a null is authoritative
    // ("actually cleared"), not just "absent from this narrower shape",
    // and must overwrite whatever was set locally before; otherwise a
    // field cleared via [completeProfile] (e.g. blanking a phone number)
    // would keep showing its old value.
    if (user.fullName != null || user.hasFullProfile) fullName = user.fullName ?? '';
    if (user.phoneNumber != null || user.hasFullProfile) phoneNumber = user.phoneNumber ?? '';
    if (user.profilePhotoUrl != null || user.hasFullProfile) profilePhotoPath = user.profilePhotoUrl;
    if (user.houseAddress != null || user.hasFullProfile) houseAddress = user.houseAddress ?? '';
    if (user.dateOfBirth != null || user.hasFullProfile) dateOfBirth = user.dateOfBirth;
    if (user.gender != null || user.hasFullProfile) gender = user.gender;
    if (user.occupation != null || user.hasFullProfile) occupation = user.occupation;
    if (user.maritalStatus != null || user.hasFullProfile) maritalStatus = user.maritalStatus;
    if (user.bio != null || user.hasFullProfile) bio = user.bio;
    if (user.hobbies.isNotEmpty || user.hasFullProfile) hobbies = user.hobbies;
    twoFactorEnabled = user.twoFactorEnabled;
    mustChangePassword = user.mustChangePassword;
    profileCompleted = user.profileCompleted;
    bankCode = user.bankCode;
    bankName = user.bankName;
    accountNumber = user.accountNumber;
    accountName = user.accountName;
    if (user.referralCode != null) myReferralCode = user.referralCode!;
    if (user.verificationStatus != null || user.hasFullProfile) {
      verificationStatus = user.verificationStatus;
      verificationNote = user.verificationNote;
      listingsHiddenUntilVerified = user.listingsHiddenUntilVerified;
    }
    notifyListeners();
  }

  void _clearSession() {
    _chatSocket.disconnect();
    userId = null;
    role = UserRole.tenant;
    email = '';
    fullName = '';
    phoneNumber = '';
    houseAddress = '';
    myReferralCode = '';
    verificationStatus = null;
    verificationNote = null;
    listingsHiddenUntilVerified = false;
    dateOfBirth = null;
    gender = null;
    occupation = null;
    maritalStatus = null;
    bio = null;
    hobbies = const [];
    profilePhotoPath = null;
    twoFactorEnabled = false;
    mustChangePassword = false;
    profileCompleted = true;
    bankCode = null;
    bankName = null;
    accountNumber = null;
    accountName = null;
    _hasVendorProfile = null;
    adminLevel = null;
    adminOnDuty = true;
    adminLevelLoadFailed = false;
    _clearListings();
    _clearBookings();
    _clearNotifications();
    _clearDevicePreferences();
    notifyListeners();
    AppIconService.apply(dashboardTheme);
  }

  Future<void> _loadInitialData() async {
    if (role == UserRole.admin) {
      await _loadAdminLevel();
      // Without this, an admin could still send/receive messages over
      // REST (ChatController has no role restriction), but would never
      // get the live "message:new" socket event — so a console chat
      // screen opened mid-session would just sit there until reopened.
      await _connectChatSocket();
      return;
    }
    await Future.wait([
      loadFavorites(),
      loadMyReviews(),
      loadNotifications(),
      if (role == UserRole.tenant) loadMyBookings(),
      if (role == UserRole.landlord) ...[loadLandlordProperties(), loadLandlordBookings()],
    ]);
    await _connectChatSocket();
  }

  AdminLevel? adminLevel;

  /// Admin console only: "On duty" gets alert sounds for new support
  /// conversations; "Away" gets them silently. Server-side (the server
  /// decides per alert whether it's silent), so it follows the admin across
  /// devices. See backend User.adminOnDuty.
  bool adminOnDuty = true;

  Future<void> setAdminOnDuty(bool value) async {
    adminOnDuty = await _adminRepo.setOnDuty(value);
    notifyListeners();
  }

  /// Admin console only, per device: whether chat alerts play a sound at
  /// all. Separate from [adminOnDuty] — this one is about this device's
  /// speakers, not the admin's availability.
  bool adminAlertSound = true;

  void setAdminAlertSound(bool value) {
    adminAlertSound = value;
    notifyListeners();
  }

  /// Admin console on web, per device: show a browser pop-up for alerts
  /// that arrive while the console tab isn't in view (another tab in front,
  /// window minimised). Only takes effect once the browser's permission has
  /// been granted — see browser_notifications_web.dart.
  bool adminBrowserNotifications = true;

  void setAdminBrowserNotifications(bool value) {
    adminBrowserNotifications = value;
    notifyListeners();
  }

  /// True once loading this admin's level has failed every attempt. The
  /// console then shows only the lowest-privilege pages, so AdminShell
  /// shows a banner with a Retry button rather than letting a super admin
  /// think they've been demoted.
  bool adminLevelLoadFailed = false;

  /// Loads this admin's level (`GET /admin/me`), retrying a few times
  /// before giving up: while the level is unknown, every moderator and
  /// super admin page is hidden, so one failed request (a slow network, or
  /// the server waking up) mustn't leave it unknown for the session.
  Future<void> _loadAdminLevel() async {
    const retryDelays = [Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8)];
    for (var attempt = 0; ; attempt++) {
      try {
        final me = await _adminRepo.me();
        adminLevel = me.level;
        adminOnDuty = me.onDuty;
        adminLevelLoadFailed = false;
        notifyListeners();
        return;
      } catch (_) {
        if (attempt >= retryDelays.length || role != UserRole.admin) {
          // Leaves it null: AdminShell shows the lowest-privilege view
          // (never guesses higher) plus the retry banner.
          adminLevelLoadFailed = true;
          notifyListeners();
          return;
        }
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  /// The console banner's Retry button.
  Future<void> retryLoadAdminLevel() async {
    adminLevelLoadFailed = false;
    notifyListeners();
    await _loadAdminLevel();
  }

  final ChatSocketService _chatSocket = ChatSocketService();

  /// One socket per session, connected right after every successful
  /// login/signup/session-restore — see ChatSocketService's doc comment
  /// for why this lives at the session level rather than per open thread.
  ChatSocketService get chatSocket => _chatSocket;

  Future<void> _connectChatSocket() async {
    final token = await _tokens.readAccessToken();
    if (token != null) {
      _chatSocket.connect(_apiClient.freshAccessToken);
      unawaited(syncWebPush());
    }
  }


  // --- Vendor profile (tenant-owned shop) ---------------------------------
  //
  // Any authenticated tenant/vendor can have a shop under the same login
  // (see vendors.controller.ts's TENANT|VENDOR role gate) — this caches
  // whether *this* account already has one, so MarketplaceAuthScreen and
  // MarketplaceNavigatorHost don't need to hit `GET /vendors/me` on every
  // rebuild. Null means "not checked yet this session"; populated lazily by
  // [checkVendorProfile] the first time something needs it, not eagerly on
  // launch.
  bool? _hasVendorProfile;
  bool? get hasVendorProfile => _hasVendorProfile;

  Future<bool> checkVendorProfile() async {
    if (_hasVendorProfile != null) return _hasVendorProfile!;
    try {
      final profile = await _vendorsRepo.findMine();
      _hasVendorProfile = profile != null;
    } catch (_) {
      // Couldn't tell either way (network error, etc.) — default to false
      // rather than leaving callers hanging; a later retry can still
      // succeed since this only short-circuits once already non-null.
      _hasVendorProfile = false;
    }
    notifyListeners();
    return _hasVendorProfile!;
  }

  /// Call right after `POST /vendors/me` succeeds so the cached flag
  /// reflects the new shop immediately, without an extra round trip.
  void markVendorProfileCreated() {
    _hasVendorProfile = true;
    notifyListeners();
  }

  /// See the subscription set up in the constructor — refetches whichever
  /// bookings list this session's role actually has, live, whenever a
  /// BOOKING_STATUS notification arrives for this user (new request,
  /// accept/decline, inspection date, payment, etc.), instead of only
  /// picking it up on the next login.
  void _handleRealtimeNotification(AppNotification notification) {
    if (notification.type != NotificationType.bookingStatus && notification.type != NotificationType.rentExpiryReminder) return;
    // An identity review decision (VerificationService.review) — refresh
    // so the profile's verification card updates without a reload.
    if (notification.title.startsWith('Your identity')) unawaited(refreshProfile().catchError((_) {}));
    // Booking notifications also cover payments, move-ins (which mark the
    // property occupied), evictions and lease ends, so reload everything
    // those touch — not just the bookings list.
    if (role == UserRole.landlord) {
      unawaited(loadLandlordBookings().catchError((_) {}));
      unawaited(loadLandlordProperties().catchError((_) {}));
    } else if (role == UserRole.tenant) {
      unawaited(loadMyBookings().catchError((_) {}));
      unawaited(loadProperties(silent: true).catchError((_) {}));
    }
  }

  DateTime? _lastRefreshAll;

  /// Fetches again everything this user's screens show — what pull-to-
  /// refresh does, and what runs when the app comes back to the foreground
  /// or the live connection reconnects (updates sent meanwhile were
  /// missed). One failing list doesn't stop the others.
  ///
  /// [ifOlderThan] skips the refresh when one ran that recently, so
  /// switching tabs/apps back and forth doesn't refetch every time.
  Future<void> refreshAll({Duration? ifOlderThan}) async {
    if (userId == null) return;
    final last = _lastRefreshAll;
    if (ifOlderThan != null && last != null && DateTime.now().difference(last) < ifOlderThan) return;
    _lastRefreshAll = DateTime.now();
    Future<void> safe(Future<void> f) => f.catchError((_) {});
    await Future.wait([
      safe(loadNotifications()),
      safe(refreshProfile()),
      if (role == UserRole.admin) safe(_loadAdminLevel()),
      if (role == UserRole.tenant) ...[safe(loadMyBookings()), safe(loadFavorites()), safe(loadMyReviews()), safe(loadProperties(silent: true))],
      if (role == UserRole.landlord) ...[safe(loadLandlordBookings()), safe(loadLandlordProperties()), safe(loadEvictions())],
    ]);
    _chatSocket.notifyThreadsChanged();
  }

  // --- Local persistence ---------------------------------------------------
  //
  // Only device-local preferences persist here — everything about the
  // signed-in user (profile, favorites, bookings, listings) is re-fetched
  // from the API on launch instead, so it can never drift stale against the
  // server the way a locally-cached copy could.
  //
  // On web, [SharedPreferences] falls back to browser `localStorage`, which
  // is shared by every tab/window on the same origin — so one user's theme
  // and notification toggles would silently apply to whoever opened the app
  // next in another tab on the same browser. [_clearSession] already resets
  // these to defaults on an explicit logout, but that does nothing for a
  // second tab open concurrently, or for a browser closed without logging
  // out first. So on web this blob goes to `sessionStorage` instead (via
  // [web_storage], isolated per tab) rather than through [SharedPreferences].

  @override
  void notifyListeners() {
    super.notifyListeners();
    unawaited(_save());
  }

  Map<String, dynamic> _toJson() => {
    // Kept so the code-entry screens survive a page reload: on a phone,
    // switching to the email app to fetch a sign-up code often reloads the
    // tab, and "Resend"/"Verify" then went out with no email at all.
    'email': email,
    'dashboardTheme': dashboardTheme.name,
    'pushNotificationsEnabled': pushNotificationsEnabled,
    'newMessageNotifications': newMessageNotifications,
    'propertyUpdateNotifications': propertyUpdateNotifications,
    'wishlistPriceDropAlerts': wishlistPriceDropAlerts,
    'promotionalNotifications': promotionalNotifications,
    'bannerAutoDismiss': bannerAutoDismiss,
    'adminAlertSound': adminAlertSound,
    'adminBrowserNotifications': adminBrowserNotifications,
    'appLockEnabled': appLockEnabled,
    // appLockPin is deliberately excluded — it lives in TokenStorage
    // (secure storage), not this plaintext SharedPreferences blob. See
    // [load]/[enableAppLock]/[disableAppLock].
  };

  void _fromJson(Map<String, dynamic> json) {
    if (email.isEmpty) email = json['email'] as String? ?? '';
    dashboardTheme = DashboardTheme.values.firstWhere(
      (t) => t.name == json['dashboardTheme'],
      orElse: () => DashboardTheme.classic,
    );
    pushNotificationsEnabled = json['pushNotificationsEnabled'] as bool? ?? true;
    newMessageNotifications = json['newMessageNotifications'] as bool? ?? true;
    propertyUpdateNotifications = json['propertyUpdateNotifications'] as bool? ?? true;
    wishlistPriceDropAlerts = json['wishlistPriceDropAlerts'] as bool? ?? true;
    promotionalNotifications = json['promotionalNotifications'] as bool? ?? false;
    bannerAutoDismiss = json['bannerAutoDismiss'] as bool? ?? true;
    adminAlertSound = json['adminAlertSound'] as bool? ?? true;
    adminBrowserNotifications = json['adminBrowserNotifications'] as bool? ?? true;
    appLockEnabled = json['appLockEnabled'] as bool? ?? false;
    // appLockPin is restored separately from secure storage — see [load].
  }

  Future<void> _save() async {
    final encoded = jsonEncode(_toJson());
    if (kIsWeb) {
      web_storage.write(_prefsKey, encoded);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, encoded);
  }

  /// Restores local prefs, then — if a session token exists — the real
  /// session from the API (profile, favorites, bookings, listings). Call
  /// once, right after construction.
  Future<void> load() async {
    final raw = kIsWeb ? web_storage.read(_prefsKey) : (await SharedPreferences.getInstance()).getString(_prefsKey);
    Map<String, dynamic>? decoded;
    if (raw != null) {
      try {
        decoded = jsonDecode(raw) as Map<String, dynamic>;
        _fromJson(decoded);
      } catch (_) {
        // Corrupt/incompatible saved state — ignore it and keep defaults.
      }
    }

    if (appLockEnabled) {
      appLockPin = await _tokens.readAppLockPin();
      // An older install may still have the PIN in plain text in this JSON
      // blob. Move it into secure storage; [_toJson] doesn't write it, so
      // it drops out of the file on the next save. If neither place has a
      // PIN, there's nothing to check against, so app lock is turned off
      // rather than locking the user out.
      if (appLockPin == null) {
        final legacyPin = decoded?['appLockPin'] as String?;
        if (legacyPin != null) {
          appLockPin = legacyPin;
          unawaited(_tokens.saveAppLockPin(legacyPin));
        } else {
          appLockEnabled = false;
        }
      }
    }

    unawaited(loadProperties());

    final accessToken = await _tokens.readAccessToken();
    if (accessToken != null) {
      restoringSession = true;
      super.notifyListeners();
      try {
        final user = await _usersRepo.me();
        _applyUser(user);
        // The admin console reads its level once on open, so have it first.
        if (role == UserRole.admin) await _loadInitialData();
      } catch (_) {
        await _tokens.clear();
      }
    }

    // Routing only needs to know who's signed in, so isLoaded is set now
    // and the lists (bookings, favorites, notifications...) load after.
    // The router ignores the session until isLoaded; waiting for every list
    // would leave a signed-in tenant on the Get Started page on a slow
    // start (e.g. coming back from Paystack).
    isLoaded = true;
    restoringSession = false;
    super.notifyListeners(); // restored data, not a change to persist again

    if (isAuthenticated && role != UserRole.admin) {
      final paymentReference = takePaymentReturnReference();
      // A marketplace order's checkout (any role can shop); otherwise a
      // tenant's rent.
      if (paymentReference != null && paymentReference.startsWith('mkto_')) {
        try {
          await _marketplaceOrdersRepo.confirmPayment(paymentReference);
        } catch (_) {
          // The webhook still marks it paid; Order History shows it then.
        }
      } else if (paymentReference != null && role == UserRole.tenant) {
        try {
          await _bookingsRepo.confirmPayment(paymentReference);
        } catch (_) {
          // The webhook still marks it paid; History refreshes when it does.
        }
      }
      try {
        await _loadInitialData();
      } catch (_) {
        // Each screen shows its own empty/error state and reloads later.
      }
    }
  }

  /// A saved session is being checked on startup — the landing page shows a
  /// loader instead of Get Started / Log In meanwhile.
  bool restoringSession = false;
}
