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
export '../api/bookings_repository.dart' show PaymentInitiation, BookingCreationResult;
import '../api/favorites_repository.dart';
import '../api/marketplace_orders_repository.dart';
import '../api/marketplace_products_repository.dart';
import '../api/models/app_notification.dart';
import '../api/models/auth_user.dart';
import '../api/models/booking.dart';
import '../api/notifications_repository.dart';
import '../api/paystack_repository.dart';
import '../api/properties_repository.dart';
import '../api/reviews_repository.dart';
import '../api/token_storage.dart';
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

/// What happened on a [AppState.login]/[AppState.loginWithGoogle] call —
/// see each method's doc comment for how a caller should react to
/// [requiresTwoFactor]/[requiresReactivation].
enum LoginOutcome { success, requiresTwoFactor, requiresReactivation }

/// Owns the app's session (real, backed by the HomeServant API) plus a
/// handful of device-local preferences (theme, notification toggles, app
/// lock) that have no server home. Session data is never persisted to
/// [SharedPreferences] — the access/refresh tokens and the app-lock PIN
/// live in the platform keychain instead (see [TokenStorage]); everything
/// else about the signed-in user is re-fetched from the API on launch via
/// [load].
class AppState extends ChangeNotifier {
  AppState() {
    _apiClient = ApiClient(_tokens)..onSessionExpired = _handleSessionExpired;
    _authRepo = AuthRepository(_apiClient, _tokens);
    _usersRepo = UsersRepository(_apiClient);
    _propertiesRepo = PropertiesRepository(_apiClient);
    _bookingsRepo = BookingsRepository(_apiClient);
    _favoritesRepo = FavoritesRepository(_apiClient);
    _reviewsRepo = ReviewsRepository(_apiClient);
    _chatRepo = ChatRepository(_apiClient);
    _uploadsRepo = UploadsRepository(_apiClient);
    _vendorsRepo = VendorsRepository(_apiClient);
    _marketplaceProductsRepo = MarketplaceProductsRepository(_apiClient);
    _marketplaceOrdersRepo = MarketplaceOrdersRepository(_apiClient);
    _paystackRepo = PaystackRepository(_apiClient);
    _notificationsRepo = NotificationsRepository(_apiClient);
    _adminRepo = AdminRepository(_apiClient);
  }

  static const _prefsKey = 'app_state_v2';

  final TokenStorage _tokens = TokenStorage();
  late final ApiClient _apiClient;
  late final AuthRepository _authRepo;
  late final UsersRepository _usersRepo;
  late final PropertiesRepository _propertiesRepo;
  late final BookingsRepository _bookingsRepo;
  late final FavoritesRepository _favoritesRepo;
  late final ReviewsRepository _reviewsRepo;
  late final ChatRepository _chatRepo;
  late final UploadsRepository _uploadsRepo;
  late final VendorsRepository _vendorsRepo;
  late final MarketplaceProductsRepository _marketplaceProductsRepo;
  late final MarketplaceOrdersRepository _marketplaceOrdersRepo;
  late final PaystackRepository _paystackRepo;
  late final NotificationsRepository _notificationsRepo;
  late final AdminRepository _adminRepo;

  /// Per-thread chat, file uploads, and the whole marketplace surface are
  /// screen-local concerns (each screen manages its own fetch/paginate) —
  /// exposed directly rather than mirrored into AppState's own fields.
  ChatRepository get chat => _chatRepo;
  UploadsRepository get uploads => _uploadsRepo;
  VendorsRepository get vendors => _vendorsRepo;
  MarketplaceProductsRepository get marketplaceProducts => _marketplaceProductsRepo;
  MarketplaceOrdersRepository get marketplaceOrders => _marketplaceOrdersRepo;
  PaystackRepository get paystack => _paystackRepo;
  AdminRepository get admin => _adminRepo;

  /// True once [load] has finished restoring (or found nothing to restore).
  /// AppLockGate waits for this before deciding whether a cold start should
  /// open locked, so it reads the setting as it was *before* this launch —
  /// not a value flipped live during the current session (see [load]).
  bool isLoaded = false;

  // --- Session -------------------------------------------------------------

  /// Null until signup/login/OTP-verify succeeds or a saved session is
  /// restored on launch — see [isAuthenticated].
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

  void acknowledgeSessionExpired() {
    sessionExpired = false;
    notifyListeners();
  }

  void _handleSessionExpired() {
    sessionExpired = true;
    // Unlike deactivateAccount()/deleteAccount(), this used to leave the
    // now-dead refresh token sitting in secure storage until the next cold
    // start's load() happened to clear it — harmless in practice (the
    // server already rejects it) but inconsistent with every other
    // forced-sign-out path.
    unawaited(_tokens.clear());
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
  MaritalStatus? maritalStatus;

  /// True for an admin still signed in with the one-time temp password
  /// from their invite email — see AuthUser.mustChangePassword.
  bool mustChangePassword = false;

  /// This user's own invite code, shown on "Invite Friends" — always
  /// real, from the server (see [_applyUser]); the backend assigns one
  /// lazily on first `GET /users/me` if an account predates this field.
  String myReferralCode = '';

  /// A local file path/blob URL while a freshly-picked photo hasn't been
  /// uploaded yet, or the persisted `https://` URL once it has — see
  /// [imageProviderForPath], which renders either.
  String? profilePhotoPath;
  bool twoFactorEnabled = false;
  DashboardTheme dashboardTheme = DashboardTheme.classic;

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

  void setProfilePhoto(String? path) {
    profilePhotoPath = path;
    notifyListeners();
  }

  // --- Auth ------------------------------------------------------------

  Future<void> signup({required String email, required String password, String? fullName}) async {
    await _authRepo.signup(email: email, password: password, role: role, fullName: fullName);
    this.email = email;
    notifyListeners();
  }

  Future<void> verifySignupOtp(String code) async {
    final user = await _authRepo.verifySignup(email: email, code: code);
    _applyUser(user);
    await refreshProfile();
    await _loadInitialData();
  }

  /// [requiresReactivation]: the account is deactivated — show a confirm
  /// prompt, then call this again with the same [email]/[password] and
  /// `reactivate: true` to actually complete the login (see
  /// AuthRepository.login). [requiresTwoFactor]: route to an OTP screen
  /// and call [verifyLoginTwoFactor] next — [email] is already set either
  /// way.
  Future<LoginOutcome> login({required String email, required String password, bool reactivate = false}) async {
    final result = await _authRepo.login(email: email, password: password, reactivate: reactivate);
    this.email = email;
    if (result.requiresReactivation) {
      notifyListeners();
      return LoginOutcome.requiresReactivation;
    }
    if (result.requiresTwoFactor) {
      notifyListeners();
      return LoginOutcome.requiresTwoFactor;
    }
    _applyUser(result.user!);
    await refreshProfile();
    await _loadInitialData();
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
  Future<LoginOutcome?> loginWithGoogle({bool reactivate = false}) async {
    final idToken = reactivate ? _pendingGoogleIdToken : await GoogleAuthService.signInAndGetIdToken();
    if (idToken == null) return null;
    _pendingGoogleIdToken = idToken;
    final result = await _authRepo.googleAuth(idToken: idToken, role: role, reactivate: reactivate);
    if (result.requiresReactivation) {
      notifyListeners();
      return LoginOutcome.requiresReactivation;
    }
    _pendingGoogleIdToken = null;
    _applyUser(result.user!);
    await refreshProfile();
    await _loadInitialData();
    return LoginOutcome.success;
  }

  Future<void> verifyLoginTwoFactor(String code) async {
    final user = await _authRepo.verifyLoginTwoFactor(email: email, code: code);
    _applyUser(user);
    await refreshProfile();
    await _loadInitialData();
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
  }) async {
    final user = await _usersRepo.updateProfile(
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
    await _authRepo.logout();
    _clearSession();
  }

  /// Hides this landlord's listings and signs out every session
  /// server-side; the account reactivates itself automatically the next
  /// time it logs in successfully (see AuthService.issueTokens).
  Future<void> deactivateAccount() async {
    await _authRepo.deactivate();
    await _tokens.clear();
    _clearSession();
  }

  /// Permanently deletes the account and everything tied to it
  /// server-side — unlike [logout]/[deactivateAccount], there is no
  /// undo.
  Future<void> deleteAccount() async {
    await _authRepo.deleteAccount();
    await _tokens.clear();
    _clearSession();
  }

  void _applyUser(AuthUser user) {
    userId = user.id;
    email = user.email;
    role = user.role;
    if (user.fullName != null) fullName = user.fullName!;
    if (user.phoneNumber != null) phoneNumber = user.phoneNumber!;
    if (user.profilePhotoUrl != null) profilePhotoPath = user.profilePhotoUrl;
    // Both absent from the narrower login/signup response shape (see
    // AuthUser's doc comment) — only ever present once the full profile's
    // been fetched, so a null here means "not fetched yet", not "cleared".
    if (user.houseAddress != null) houseAddress = user.houseAddress!;
    if (user.dateOfBirth != null) dateOfBirth = user.dateOfBirth;
    if (user.gender != null) gender = user.gender;
    if (user.occupation != null) occupation = user.occupation;
    if (user.maritalStatus != null) maritalStatus = user.maritalStatus;
    twoFactorEnabled = user.twoFactorEnabled;
    mustChangePassword = user.mustChangePassword;
    bankCode = user.bankCode;
    bankName = user.bankName;
    accountNumber = user.accountNumber;
    accountName = user.accountName;
    if (user.referralCode != null) myReferralCode = user.referralCode!;
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
    dateOfBirth = null;
    gender = null;
    occupation = null;
    maritalStatus = null;
    profilePhotoPath = null;
    twoFactorEnabled = false;
    mustChangePassword = false;
    bankCode = null;
    bankName = null;
    accountNumber = null;
    accountName = null;
    _favorites = [];
    _landlordProperties = [];
    myBookings = [];
    landlordBookings = [];
    _myReviews = [];
    notifications = [];
    unreadNotificationCount = 0;
    _hasVendorProfile = null;
    adminLevel = null;
    pushNotificationsEnabled = true;
    newMessageNotifications = true;
    propertyUpdateNotifications = true;
    wishlistPriceDropAlerts = true;
    promotionalNotifications = false;
    bannerAutoDismiss = true;
    appLockEnabled = false;
    appLockPin = null;
    unawaited(_tokens.clearAppLockPin());
    dashboardTheme = DashboardTheme.classic;
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

  Future<void> _loadAdminLevel() async {
    try {
      adminLevel = await _adminRepo.myLevel();
      notifyListeners();
    } catch (_) {
      // Leaves it null — AdminShell treats that the same as "not yet
      // loaded" and shows the lowest-privilege view until a retry
      // succeeds, rather than guessing.
    }
  }

  final ChatSocketService _chatSocket = ChatSocketService();

  /// One socket per session, connected right after every successful
  /// login/signup/session-restore — see ChatSocketService's doc comment
  /// for why this lives at the session level rather than per open thread.
  ChatSocketService get chatSocket => _chatSocket;

  Future<void> _connectChatSocket() async {
    final token = await _tokens.readAccessToken();
    if (token != null) _chatSocket.connect(token);
  }

  // --- Notifications -----------------------------------------------------

  List<AppNotification> notifications = [];
  int unreadNotificationCount = 0;

  Future<void> loadNotifications() async {
    try {
      final results = await Future.wait([_notificationsRepo.findMine(), _notificationsRepo.unreadCount()]);
      notifications = results[0] as List<AppNotification>;
      unreadNotificationCount = results[1] as int;
      notifyListeners();
    } catch (_) {
      // Leaves whatever was last loaded (or the empty default) in place —
      // the bell/list just won't reflect anything newer until the next
      // successful load.
    }
  }

  Future<void> markNotificationRead(String id) async {
    final index = notifications.indexWhere((n) => n.id == id);
    if (index == -1 || notifications[index].isRead) return;
    await _notificationsRepo.markRead(id);
    notifications[index] = AppNotification(
      id: notifications[index].id,
      type: notifications[index].type,
      title: notifications[index].title,
      body: notifications[index].body,
      createdAt: notifications[index].createdAt,
      readAt: DateTime.now(),
    );
    unreadNotificationCount = (unreadNotificationCount - 1).clamp(0, 1 << 30);
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    if (unreadNotificationCount == 0) return;
    await _notificationsRepo.markAllRead();
    notifications = [
      for (final n in notifications)
        AppNotification(id: n.id, type: n.type, title: n.title, body: n.body, createdAt: n.createdAt, readAt: n.readAt ?? DateTime.now()),
    ];
    unreadNotificationCount = 0;
    notifyListeners();
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

  // --- Properties (public browse feed) --------------------------------

  List<Property> properties = [];
  bool propertiesLoading = false;

  Future<void> loadProperties({String? state, String? category}) async {
    propertiesLoading = true;
    notifyListeners();
    try {
      properties = await _propertiesRepo.findMany(state: state, category: category);
    } finally {
      propertiesLoading = false;
      notifyListeners();
    }
  }

  // --- Landlord: properties added through "Add Property" ----------------

  List<Property> _landlordProperties = [];
  List<Property> get landlordProperties => List.unmodifiable(_landlordProperties);

  Future<void> loadLandlordProperties() async {
    final id = userId;
    if (id == null) return;
    _landlordProperties = await _propertiesRepo.findMany(landlordId: id);
    notifyListeners();
  }

  Future<Property> addLandlordProperty(Property property) async {
    final created = await _propertiesRepo.create(property);
    _landlordProperties = [created, ..._landlordProperties];
    notifyListeners();
    return created;
  }

  /// Full re-edit (rent duration, messaging toggle, shortlet fields, etc.)
  /// of an existing listing — `PATCH /properties/:id`.
  Future<Property> updateLandlordProperty(Property property) async {
    final updated = await _propertiesRepo.update(property.id, property.toUpdateJson());
    _landlordProperties = [for (final p in _landlordProperties) if (p.id == updated.id) updated else p];
    notifyListeners();
    return updated;
  }

  /// Just the per-property messaging toggle — used from the listing edit
  /// screen without resubmitting every other field.
  Future<Property> setPropertyMessagingEnabled(String propertyId, bool enabled) async {
    final updated = await _propertiesRepo.update(propertyId, {'messagingEnabled': enabled});
    _landlordProperties = [for (final p in _landlordProperties) if (p.id == updated.id) updated else p];
    notifyListeners();
    return updated;
  }

  // --- Wishlist ----------------------------------------------------------

  List<Property> _favorites = [];
  Set<String> get favoritePropertyIds => _favorites.map((p) => p.id).toSet();
  List<Property> get favoriteProperties => List.unmodifiable(_favorites);

  bool isFavorite(String propertyId) => _favorites.any((p) => p.id == propertyId);

  Future<void> loadFavorites() async {
    if (userId == null) return;
    _favorites = await _favoritesRepo.mine();
    notifyListeners();
  }

  /// Optimistic: flips local state immediately (so the heart icon responds
  /// instantly) and reconciles with the server in the background, reverting
  /// by refetching if the request fails.
  Future<void> toggleFavorite(String propertyId) async {
    if (userId == null) return;
    final wasFavorited = isFavorite(propertyId);
    if (wasFavorited) {
      _favorites = _favorites.where((p) => p.id != propertyId).toList();
    } else {
      final match = properties.where((p) => p.id == propertyId);
      if (match.isNotEmpty) _favorites = [..._favorites, match.first];
    }
    notifyListeners();
    try {
      await _favoritesRepo.toggle(propertyId);
    } catch (_) {
      await loadFavorites();
    }
  }

  // --- Bookings & rental history ------------------------------------------

  List<Booking> myBookings = [];
  List<Booking> landlordBookings = [];
  List<_ReviewSummary> _myReviews = [];

  /// This tenant's own star rating for [propertyId], if they've rated it —
  /// used by history/booking tiles instead of the removed derived
  /// `RentalRecord` map.
  double? myReviewFor(String propertyId) {
    final match = _myReviews.where((r) => r.propertyId == propertyId);
    return match.isEmpty ? null : match.first.rating;
  }

  Future<void> loadMyBookings() async {
    if (userId == null) return;
    myBookings = await _bookingsRepo.mine();
    notifyListeners();
  }

  Future<void> loadLandlordBookings() async {
    if (userId == null) return;
    landlordBookings = await _bookingsRepo.forLandlord();
    notifyListeners();
  }

  Future<void> respondToBooking(String id, {required bool accepted}) async {
    final updated = await _bookingsRepo.respond(id: id, accepted: accepted);
    landlordBookings = [for (final b in landlordBookings) if (b.id == id) updated else b];
    notifyListeners();
  }

  /// For a Shortlet property, sends a booking request to the landlord
  /// (unchanged flow: request → landlord `respond`s → tenant `pay`s
  /// separately). For a non-Shortlet property, creates the booking and
  /// immediately starts its Paystack charge — [BookingCreationResult.payment]
  /// is set in that case; open its `authorizationUrl` right away. [nights]
  /// is required only when [isShortlet].
  Future<BookingCreationResult> recordRentalOrBooking(String propertyId, {required bool isShortlet, int? nights}) async {
    final result = await _bookingsRepo.create(propertyId: propertyId, isShortlet: isShortlet, nights: isShortlet ? nights : null);
    myBookings = [result.booking, ...myBookings];
    notifyListeners();
    return result;
  }

  /// Starts a Paystack charge for [bookingId] — open the returned
  /// authorization URL in a browser/webview. Also usable as a retry if a
  /// create-time charge attempt didn't finish.
  Future<PaymentInitiation> payForBooking(String bookingId) => _bookingsRepo.pay(bookingId);

  Future<void> markBookingMovedIn(String bookingId) async {
    final updated = await _bookingsRepo.markMovedIn(bookingId);
    myBookings = [for (final b in myBookings) if (b.id == bookingId) updated else b];
    notifyListeners();
  }

  Future<void> refundBooking(String bookingId) async {
    final updated = await _bookingsRepo.refund(bookingId);
    myBookings = [for (final b in myBookings) if (b.id == bookingId) updated else b];
    notifyListeners();
  }

  Future<void> renewBooking(String bookingId) async {
    final updated = await _bookingsRepo.renew(bookingId);
    myBookings = [for (final b in myBookings) if (b.id == bookingId) updated else b];
    notifyListeners();
  }

  Future<TenancyAgreement?> fetchTenancyAgreement(String bookingId) => _bookingsRepo.tenancyAgreement(bookingId);

  /// Tenant proposes (or re-proposes) an inspection date for a
  /// PAID_AWAITING_INSPECTION booking — reachable any time from history,
  /// including right after paying ("book later") or much later.
  Future<void> proposeInspection(String bookingId, DateTime requestedDate) async {
    final updated = await _bookingsRepo.proposeInspection(id: bookingId, requestedDate: requestedDate);
    myBookings = [for (final b in myBookings) if (b.id == bookingId) updated else b];
    notifyListeners();
  }

  /// Landlord accepts/declines the tenant's specific proposed inspection
  /// date — distinct from [rejectBooking], which ends the booking outright.
  Future<void> respondToInspection(String bookingId, {required bool accepted}) async {
    final updated = await _bookingsRepo.respondToInspection(id: bookingId, accepted: accepted);
    landlordBookings = [for (final b in landlordBookings) if (b.id == bookingId) updated else b];
    notifyListeners();
  }

  /// Landlord's distinct "reject this booking outright" lever — full
  /// refund, no platform fee withheld.
  Future<void> rejectBooking(String bookingId) async {
    final updated = await _bookingsRepo.rejectBooking(bookingId);
    landlordBookings = [for (final b in landlordBookings) if (b.id == bookingId) updated else b];
    notifyListeners();
  }

  Future<void> loadMyReviews() async {
    if (userId == null) return;
    final reviews = await _reviewsRepo.mine();
    _myReviews = [for (final r in reviews) _ReviewSummary(propertyId: r.propertyId, rating: r.rating.toDouble())];
    notifyListeners();
  }

  Future<void> rateHistoryProperty(String propertyId, double rating) async {
    await _reviewsRepo.upsert(propertyId: propertyId, rating: rating.round());
    await loadMyReviews();
  }

  // --- Notification preferences (device-local, no server model) ----------

  bool pushNotificationsEnabled = true;
  bool newMessageNotifications = true;
  bool propertyUpdateNotifications = true;
  // Ties directly into the Wishlist feature — lets a tenant know the moment
  // a house they've saved gets cheaper, without having to keep re-checking it.
  bool wishlistPriceDropAlerts = true;
  bool promotionalNotifications = false;

  void setPushNotificationsEnabled(bool value) {
    pushNotificationsEnabled = value;
    notifyListeners();
  }

  void setNewMessageNotifications(bool value) {
    newMessageNotifications = value;
    notifyListeners();
  }

  void setPropertyUpdateNotifications(bool value) {
    propertyUpdateNotifications = value;
    notifyListeners();
  }

  void setWishlistPriceDropAlerts(bool value) {
    wishlistPriceDropAlerts = value;
    notifyListeners();
  }

  void setPromotionalNotifications(bool value) {
    promotionalNotifications = value;
    notifyListeners();
  }

  /// Controls the global Instagram-style banner shown by
  /// NotificationBannerOverlay the instant a `notification:new` socket
  /// event arrives: `true` (default) auto-dismisses it after ~3s; `false`
  /// leaves it up until the user swipes it away. Purely a display
  /// preference (no server model), same as the rest of this section.
  bool bannerAutoDismiss = true;

  void setBannerAutoDismiss(bool value) {
    bannerAutoDismiss = value;
    notifyListeners();
  }

  // --- Security: app lock (device-local) ----------------------------------

  bool appLockEnabled = false;
  String? appLockPin;

  void enableAppLock(String pin) {
    appLockEnabled = true;
    appLockPin = pin;
    unawaited(_tokens.saveAppLockPin(pin));
    notifyListeners();
  }

  void disableAppLock() {
    appLockEnabled = false;
    appLockPin = null;
    unawaited(_tokens.clearAppLockPin());
    notifyListeners();
  }

  void setDashboardTheme(DashboardTheme theme) {
    dashboardTheme = theme;
    notifyListeners();
    AppIconService.apply(theme);
  }

  // --- Local persistence ---------------------------------------------------
  //
  // Only device-local preferences persist here — everything about the
  // signed-in user (profile, favorites, bookings, listings) is re-fetched
  // from the API on launch instead, so it can never drift stale against the
  // server the way a locally-cached copy could.

  @override
  void notifyListeners() {
    super.notifyListeners();
    unawaited(_save());
  }

  Map<String, dynamic> _toJson() => {
    'dashboardTheme': dashboardTheme.name,
    'pushNotificationsEnabled': pushNotificationsEnabled,
    'newMessageNotifications': newMessageNotifications,
    'propertyUpdateNotifications': propertyUpdateNotifications,
    'wishlistPriceDropAlerts': wishlistPriceDropAlerts,
    'promotionalNotifications': promotionalNotifications,
    'bannerAutoDismiss': bannerAutoDismiss,
    'appLockEnabled': appLockEnabled,
    // appLockPin is deliberately excluded — it lives in TokenStorage
    // (secure storage), not this plaintext SharedPreferences blob. See
    // [load]/[enableAppLock]/[disableAppLock].
  };

  void _fromJson(Map<String, dynamic> json) {
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
    appLockEnabled = json['appLockEnabled'] as bool? ?? false;
    // appLockPin is restored separately from secure storage — see [load].
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_toJson()));
  }

  /// Restores local prefs, then — if a session token exists — the real
  /// session from the API (profile, favorites, bookings, listings). Call
  /// once, right after construction.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
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
      // One-time migration for installs saved before the PIN moved to
      // secure storage: a legacy plaintext copy may still be in this JSON
      // blob. Adopt it into secure storage once; the field is no longer
      // written by [_toJson], so it naturally drops out of the file on the
      // next save. If neither source has a PIN, app lock can't be honored,
      // so turn it back off rather than locking the user out with nothing
      // to check against.
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
      try {
        final user = await _usersRepo.me();
        _applyUser(user);
        await _loadInitialData();
      } catch (_) {
        await _tokens.clear();
      }
    }

    isLoaded = true;
    super.notifyListeners(); // restored data, not a change to persist again
  }
}

class _ReviewSummary {
  const _ReviewSummary({required this.propertyId, required this.rating});
  final String propertyId;
  final double rating;
}
