import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/auth_repository.dart';
import '../api/bookings_repository.dart';
import '../api/chat_repository.dart';
import '../api/favorites_repository.dart';
import '../api/models/auth_user.dart';
import '../api/models/booking.dart';
import '../api/properties_repository.dart';
import '../api/reviews_repository.dart';
import '../api/token_storage.dart';
import '../api/uploads_repository.dart';
import '../api/users_repository.dart';
import '../features/dashboard/models/property.dart';
import '../features/dashboard/models/rental_record.dart';
import '../models/dashboard_theme.dart';
import '../models/user_role.dart';
import '../services/app_icon_service.dart';

/// Owns the app's session (real, backed by the HomeServant API) plus a
/// handful of device-local preferences (theme, notification toggles, app
/// lock) that have no server home. Session data is never persisted to
/// [SharedPreferences] — only the access/refresh tokens are (in the
/// platform keychain, see [TokenStorage]); everything else about the
/// signed-in user is re-fetched from the API on launch via [load].
class AppState extends ChangeNotifier {
  AppState() {
    _apiClient = ApiClient(_tokens)..onSessionExpired = _clearSession;
    _authRepo = AuthRepository(_apiClient, _tokens);
    _usersRepo = UsersRepository(_apiClient);
    _propertiesRepo = PropertiesRepository(_apiClient);
    _bookingsRepo = BookingsRepository(_apiClient);
    _favoritesRepo = FavoritesRepository(_apiClient);
    _reviewsRepo = ReviewsRepository(_apiClient);
    _chatRepo = ChatRepository(_apiClient);
    _uploadsRepo = UploadsRepository(_apiClient);
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

  /// Per-thread chat and file uploads are screen-local concerns (a chat
  /// screen manages its own paginated messages) — exposed directly rather
  /// than mirrored into AppState's own fields.
  ChatRepository get chat => _chatRepo;
  UploadsRepository get uploads => _uploadsRepo;

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

  UserRole role = UserRole.tenant;
  String email = '';
  String fullName = '';
  String phoneNumber = '';
  String houseAddress = '';
  String referralCode = '';
  DateTime? dateOfBirth;

  /// A local file path/blob URL while a freshly-picked photo hasn't been
  /// uploaded yet, or the persisted `https://` URL once it has — see
  /// [imageProviderForPath], which renders either.
  String? profilePhotoPath;
  bool twoFactorEnabled = false;
  DashboardTheme dashboardTheme = DashboardTheme.classic;

  void selectRole(UserRole newRole) {
    role = newRole;
    notifyListeners();
  }

  void setEmail(String value) {
    email = value;
    notifyListeners();
  }

  /// Stages fields collected before an account exists yet (mid-signup) —
  /// [referralCode] has no server home so it only ever lives here;
  /// name/phone/houseAddress are re-sent to the server via
  /// [completeProfile] once the account does exist.
  void setProfileBasics({required String name, required String phone, String? houseAddress, String? referralCode}) {
    fullName = name;
    phoneNumber = phone;
    if (houseAddress != null) this.houseAddress = houseAddress;
    if (referralCode != null) this.referralCode = referralCode;
    notifyListeners();
  }

  void setProfilePhoto(String? path) {
    profilePhotoPath = path;
    notifyListeners();
  }

  /// Generates a shareable referral code the first time it's needed (e.g.
  /// opening "Invite Friends") if signup never set one.
  String ensureReferralCode() {
    if (referralCode.isNotEmpty) return referralCode;
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    referralCode = 'HS-${List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join()}';
    notifyListeners();
    return referralCode;
  }

  // --- Auth ------------------------------------------------------------

  Future<void> signup({required String email, required String password}) async {
    await _authRepo.signup(email: email, password: password, role: role);
    this.email = email;
    notifyListeners();
  }

  Future<void> verifySignupOtp(String code) async {
    final user = await _authRepo.verifySignup(email: email, code: code);
    _applyUser(user);
    await _loadInitialData();
  }

  /// Returns `true` once fully logged in, `false` if the account has 2FA on
  /// (the caller should route to an OTP screen and call
  /// [verifyLoginTwoFactor] next — [email] is already set either way).
  Future<bool> login({required String email, required String password}) async {
    final result = await _authRepo.login(email: email, password: password);
    this.email = email;
    if (result.requiresTwoFactor) {
      notifyListeners();
      return false;
    }
    _applyUser(result.user!);
    await _loadInitialData();
    return true;
  }

  Future<void> verifyLoginTwoFactor(String code) async {
    final user = await _authRepo.verifyLoginTwoFactor(email: email, code: code);
    _applyUser(user);
    await _loadInitialData();
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) {
    return _authRepo.changePassword(currentPassword: currentPassword, newPassword: newPassword);
  }

  Future<void> completeProfile({
    String? fullName,
    String? phoneNumber,
    String? houseAddress,
    DateTime? dateOfBirth,
    String? profilePhotoUrl,
  }) async {
    final user = await _usersRepo.updateProfile(
      fullName: fullName,
      phoneNumber: phoneNumber,
      houseAddress: houseAddress,
      dateOfBirth: dateOfBirth,
      profilePhotoUrl: profilePhotoUrl,
    );
    _applyUser(user);
    if (houseAddress != null) this.houseAddress = houseAddress;
    notifyListeners();
  }

  Future<void> setTwoFactorEnabled(bool value) async {
    final user = await _usersRepo.updateProfile(twoFactorEnabled: value);
    _applyUser(user);
  }

  Future<void> logout() async {
    await _authRepo.logout();
    _clearSession();
  }

  /// Deactivating/deleting both just end the local session today — there's
  /// no backend endpoint yet to flag the account inactive or erase it. Kept
  /// as their own methods, distinct from [logout], so wiring a real
  /// endpoint later has a clear place to do it.
  Future<void> deactivateAccount() => logout();
  Future<void> deleteAccount() => logout();

  void _applyUser(AuthUser user) {
    userId = user.id;
    email = user.email;
    role = user.role;
    if (user.fullName != null) fullName = user.fullName!;
    if (user.phoneNumber != null) phoneNumber = user.phoneNumber!;
    if (user.profilePhotoUrl != null) profilePhotoPath = user.profilePhotoUrl;
    twoFactorEnabled = user.twoFactorEnabled;
    notifyListeners();
  }

  void _clearSession() {
    userId = null;
    role = UserRole.tenant;
    email = '';
    fullName = '';
    phoneNumber = '';
    houseAddress = '';
    referralCode = '';
    dateOfBirth = null;
    profilePhotoPath = null;
    twoFactorEnabled = false;
    _favorites = [];
    _landlordProperties = [];
    myBookings = [];
    landlordBookings = [];
    _myReviews = [];
    _rentalHistory = {};
    pushNotificationsEnabled = true;
    newMessageNotifications = true;
    propertyUpdateNotifications = true;
    wishlistPriceDropAlerts = true;
    promotionalNotifications = false;
    appLockEnabled = false;
    appLockPin = null;
    landlordMessagesEnabled = true;
    dashboardTheme = DashboardTheme.classic;
    notifyListeners();
    AppIconService.apply(dashboardTheme);
  }

  Future<void> _loadInitialData() async {
    await Future.wait([
      loadFavorites(),
      loadMyReviews(),
      if (role == UserRole.tenant) loadMyBookings(),
      if (role == UserRole.landlord) ...[loadLandlordProperties(), loadLandlordBookings()],
    ]);
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
  Map<String, RentalRecord> _rentalHistory = {};

  Map<String, RentalRecord> get rentalHistory => Map.unmodifiable(_rentalHistory);

  Future<void> loadMyBookings() async {
    if (userId == null) return;
    myBookings = await _bookingsRepo.mine();
    _rebuildRentalHistory();
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

  /// Sends a real booking request to the landlord — no longer an instant
  /// local "success", so [rentalHistory] only reflects bookings the
  /// landlord has actually accepted (see [_rebuildRentalHistory]).
  Future<void> recordRentalOrBooking(String propertyId, {required bool isShortlet}) async {
    final booking = await _bookingsRepo.create(propertyId: propertyId);
    myBookings = [booking, ...myBookings];
    _rebuildRentalHistory();
    notifyListeners();
  }

  Future<void> loadMyReviews() async {
    if (userId == null) return;
    final reviews = await _reviewsRepo.mine();
    _myReviews = [for (final r in reviews) _ReviewSummary(propertyId: r.propertyId, rating: r.rating.toDouble())];
    _rebuildRentalHistory();
    notifyListeners();
  }

  Future<void> rateHistoryProperty(String propertyId, double rating) async {
    await _reviewsRepo.upsert(propertyId: propertyId, rating: rating.round());
    await loadMyReviews();
  }

  /// [RentalRecord]s are derived, not stored directly — an ACCEPTED booking
  /// becomes one, with an end date synthesised the same way the old
  /// local-only mock did (the API doesn't model a lease term yet), and the
  /// tenant's own review rating (if any) merged in.
  void _rebuildRentalHistory() {
    final history = <String, RentalRecord>{};
    for (final booking in myBookings) {
      if (booking.status != BookingStatus.accepted) continue;
      final isShortlet = booking.property.category == 'Shortlet';
      final start = booking.createdAt;
      final end = start.add(Duration(days: isShortlet ? 3 : 365));
      final ratingMatch = _myReviews.where((r) => r.propertyId == booking.property.id);
      history[booking.property.id] = RentalRecord(
        startDate: start,
        endDate: end,
        rating: ratingMatch.isEmpty ? null : ratingMatch.first.rating,
      );
    }
    _rentalHistory = history;
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

  // --- Landlord: tenant messaging (device-local, no server model) --------

  /// Whether tenants can message this landlord — and, from there, book a
  /// property inspection. Landlord-only setting; when off, a tenant's
  /// property detail screen hides "Message Landlord" entirely, leaving rent
  /// payment as the only way forward.
  bool landlordMessagesEnabled = true;

  void setLandlordMessagesEnabled(bool value) {
    landlordMessagesEnabled = value;
    notifyListeners();
  }

  // --- Security: app lock (device-local) ----------------------------------

  bool appLockEnabled = false;
  String? appLockPin;

  void enableAppLock(String pin) {
    appLockEnabled = true;
    appLockPin = pin;
    notifyListeners();
  }

  void disableAppLock() {
    appLockEnabled = false;
    appLockPin = null;
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
    'appLockEnabled': appLockEnabled,
    'appLockPin': appLockPin,
    'landlordMessagesEnabled': landlordMessagesEnabled,
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
    appLockEnabled = json['appLockEnabled'] as bool? ?? false;
    appLockPin = json['appLockPin'] as String?;
    landlordMessagesEnabled = json['landlordMessagesEnabled'] as bool? ?? true;
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
    if (raw != null) {
      try {
        _fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // Corrupt/incompatible saved state — ignore it and keep defaults.
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
