part of '../app_state.dart';

/// Bookings for both sides (the tenant's own and the landlord's incoming),
/// eviction requests on them, and the tenant's ratings of past rentals.
mixin _BookingsSection on ChangeNotifier {
  String? get userId;
  BookingsRepository get _bookingsRepo;
  EvictionsRepository get _evictionsRepo;
  ReviewsRepository get _reviewsRepo;

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
    unawaited(loadEvictions());
  }

  /// Clears requests from the landlord's home feed (or restores them, for
  /// Undo), then refreshes. Nothing is declined.
  Future<void> setIncomingFeedCleared({required bool cleared, List<String>? bookingIds}) async {
    await _bookingsRepo.setFeedCleared(cleared: cleared, bookingIds: bookingIds);
    await loadLandlordBookings();
  }

  Future<void> loadLandlordBookings() async {
    if (userId == null) return;
    landlordBookings = await _bookingsRepo.forLandlord();
    notifyListeners();
    unawaited(loadEvictions());
  }

  // --- Eviction requests (landlord files, tenant responds, super admin decides)

  /// Every eviction request this user is a party to, newest first.
  List<EvictionRequest> evictions = [];

  /// The most recent eviction request on [bookingId], if any.
  EvictionRequest? evictionForBooking(String bookingId) {
    for (final e in evictions) {
      if (e.bookingId == bookingId) return e;
    }
    return null;
  }

  /// Refreshed with the bookings lists (so a BOOKING_STATUS notification,
  /// which every eviction event also sends, updates it live). Best-effort:
  /// a failure here must never break the bookings screens.
  Future<void> loadEvictions() async {
    if (userId == null) return;
    try {
      evictions = await _evictionsRepo.mine();
      notifyListeners();
    } catch (_) {}
  }

  void _upsertEviction(EvictionRequest updated) {
    evictions = [updated, for (final e in evictions) if (e.id != updated.id) e];
    notifyListeners();
  }

  Future<void> requestEviction(String bookingId, String reason) async {
    _upsertEviction(await _evictionsRepo.create(bookingId, reason));
  }

  Future<void> cancelEviction(String id) async {
    _upsertEviction(await _evictionsRepo.cancel(id));
  }

  Future<void> respondToEviction(String id, String response) async {
    _upsertEviction(await _evictionsRepo.respond(id, response));
  }

  Future<void> respondToBooking(String id, {required bool accepted}) async {
    await _bookingsRepo.respond(id: id, accepted: accepted);
    await loadLandlordBookings();
  }

  /// For a Shortlet property, sends a booking request to the landlord
  /// (unchanged flow: request → landlord `respond`s → tenant `pay`s
  /// separately). For a non-Shortlet property, creates the booking and
  /// immediately starts its Paystack charge — [BookingCreationResult.payment]
  /// is set in that case; open its `authorizationUrl` right away. [nights]
  /// is required only when [isShortlet].
  Future<BookingCreationResult> recordRentalOrBooking(
    String propertyId, {
    required bool isShortlet,
    int? nights,
    bool payMonthly = false,
  }) async {
    final result = await _bookingsRepo.create(
      propertyId: propertyId,
      isShortlet: isShortlet,
      nights: isShortlet ? nights : null,
      payMonthly: payMonthly,
    );
    // The server continues an unfinished checkout rather than creating a
    // second booking, so the same id can come back.
    myBookings = [result.booking, ...myBookings.where((b) => b.id != result.booking.id)];
    notifyListeners();
    return result;
  }

  /// Starts a Paystack charge for [bookingId] — open the returned
  /// authorization URL in a browser/webview. Also usable as a retry if a
  /// create-time charge attempt didn't finish.
  Future<PaymentInitiation> payForBooking(String bookingId) => _bookingsRepo.pay(bookingId);

  Future<void> markBookingMovedIn(String bookingId) async {
    await _bookingsRepo.markMovedIn(bookingId);
    await loadMyBookings();
  }

  Future<void> refundBooking(String bookingId) async {
    await _bookingsRepo.refund(bookingId);
    await loadMyBookings();
  }

  Future<RenewalQuote> renewalQuote(String bookingId) => _bookingsRepo.renewalQuote(bookingId);

  /// Monthly plan: pay next month's rent (opens checkout).
  Future<PaymentInitiation> payNextMonth(String bookingId) => _bookingsRepo.payNextMonth(bookingId);

  /// Starts the renewal payment for the amount in [quote]; the lease is
  /// extended once Paystack confirms it (the bookings list refreshes then).
  Future<PaymentInitiation> renewBooking(String bookingId, RenewalQuote quote) => _bookingsRepo.renew(bookingId, quote);

  Future<TenancyAgreement?> fetchTenancyAgreement(String bookingId) => _bookingsRepo.tenancyAgreement(bookingId);

  /// Tenant proposes (or re-proposes) an inspection date for a
  /// PAID_AWAITING_INSPECTION booking — reachable any time from history,
  /// including right after paying ("book later") or much later.
  Future<void> proposeInspection(String bookingId, DateTime requestedDate) async {
    await _bookingsRepo.proposeInspection(id: bookingId, requestedDate: requestedDate);
    await loadMyBookings();
  }

  /// Landlord accepts/declines the tenant's specific proposed inspection
  /// date — distinct from [rejectBooking], which ends the booking outright.
  Future<void> respondToInspection(String bookingId, {required bool accepted}) async {
    await _bookingsRepo.respondToInspection(id: bookingId, accepted: accepted);
    await loadLandlordBookings();
  }

  /// Landlord sets the inspection date themselves (no tenant proposal
  /// needed, or instead of the one proposed).
  Future<void> scheduleInspection(String bookingId, DateTime date) async {
    await _bookingsRepo.scheduleInspection(id: bookingId, date: date);
    await loadLandlordBookings();
  }

  /// Landlord's distinct "reject this booking outright" lever — full
  /// refund, no platform fee withheld.
  Future<void> rejectBooking(String bookingId) async {
    await _bookingsRepo.rejectBooking(bookingId);
    await loadLandlordBookings();
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

  /// Called on logout.
  void _clearBookings() {
    myBookings = [];
    landlordBookings = [];
    evictions = [];
    _myReviews = [];
  }
}

class _ReviewSummary {
  const _ReviewSummary({required this.propertyId, required this.rating});
  final String propertyId;
  final double rating;
}
