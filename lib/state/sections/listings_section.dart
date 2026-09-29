part of '../app_state.dart';

/// Property lists: the public browse feed, the landlord's own listings,
/// and the tenant's wishlist.
mixin _ListingsSection on ChangeNotifier {
  String? get userId;
  PropertiesRepository get _propertiesRepo;
  FavoritesRepository get _favoritesRepo;

  // --- Properties (public browse feed) --------------------------------

  List<Property> properties = [];
  bool propertiesLoading = false;

  /// [silent]: a background refresh — the list swaps in place without
  /// showing the loading state first.
  Future<void> loadProperties({String? state, String? category, bool silent = false}) async {
    if (!silent) {
      propertiesLoading = true;
      notifyListeners();
    }
    try {
      properties = await _propertiesRepo.findMany(state: state, category: category);
    } finally {
      propertiesLoading = false;
      notifyListeners();
    }
  }

  /// Fetches a single property fresh from the server — used by
  /// PropertyDetailScreen so a price/availability change made elsewhere
  /// (another tab, another session, an admin edit) shows up even when the
  /// screen was opened from an already-stale list, instead of only ever
  /// trusting the snapshot it was handed.
  Future<Property> fetchProperty(String id) => _propertiesRepo.findOne(id);

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

  /// Hides an unoccupied listing from browse, search and booking (or shows
  /// it again) — `PATCH /properties/:id` with `isHidden`. The server
  /// refuses to hide an occupied listing, with the reason.
  Future<Property> setLandlordPropertyHidden(String id, bool hidden) async {
    final updated = await _propertiesRepo.update(id, {'isHidden': hidden});
    _landlordProperties = [for (final p in _landlordProperties) if (p.id == updated.id) updated else p];
    if (hidden) properties = [for (final p in properties) if (p.id != id) p];
    notifyListeners();
    return updated;
  }

  /// `DELETE /properties/:id`. The server refuses while the property is
  /// occupied or a tenant's payment is in play (PropertiesService
  /// .deletionBlockReason) — that ApiException's message says why.
  Future<void> deleteLandlordProperty(String id) async {
    await _propertiesRepo.remove(id);
    _landlordProperties = [for (final p in _landlordProperties) if (p.id != id) p];
    properties = [for (final p in properties) if (p.id != id) p];
    _favorites = [for (final p in _favorites) if (p.id != id) p];
    notifyListeners();
  }

  // --- Wishlist ----------------------------------------------------------

  List<Property> _favorites = [];
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
    // The "add" branch can only build the optimistic entry from the cached
    // browse list ([properties]) — if the property being favorited isn't
    // in it (viewed via its own detail fetch instead, a different filter
    // was last loaded, or it's past that list's page-size cap), there's
    // nothing to optimistically render, so this falls through to
    // [loadFavorites] below instead of silently leaving the heart looking
    // unfavorited despite the toggle having actually succeeded.
    var appliedOptimistically = false;
    if (wasFavorited) {
      _favorites = _favorites.where((p) => p.id != propertyId).toList();
      appliedOptimistically = true;
    } else {
      final match = properties.where((p) => p.id == propertyId);
      if (match.isNotEmpty) {
        _favorites = [..._favorites, match.first];
        appliedOptimistically = true;
      }
    }
    notifyListeners();
    try {
      await _favoritesRepo.toggle(propertyId);
      if (!appliedOptimistically) await loadFavorites();
    } catch (_) {
      await loadFavorites();
    }
  }

  /// Called on logout. The public browse feed is kept: it's the same for
  /// everyone.
  void _clearListings() {
    _favorites = [];
    _landlordProperties = [];
  }
}
