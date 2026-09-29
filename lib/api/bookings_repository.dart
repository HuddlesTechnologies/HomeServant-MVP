import 'api_client.dart';
import 'api_exception.dart';
import 'models/booking.dart';
import 'models/tenancy_agreement.dart';

/// `POST /bookings/:id/pay`'s response — Paystack's hosted checkout page to
/// open in a webview/browser, plus the reference to reconcile against later.
class PaymentInitiation {
  const PaymentInitiation({required this.authorizationUrl, required this.reference});

  final String authorizationUrl;
  final String reference;

  factory PaymentInitiation.fromApi(Map<String, dynamic> json) => PaymentInitiation(
    authorizationUrl: json['authorizationUrl'] as String,
    reference: json['reference'] as String,
  );
}

/// GET /bookings/:id/renewal-quote. Amounts are whole naira.
class RenewalQuote {
  const RenewalQuote({
    required this.amount,
    required this.priceUnit,
    required this.leaseMonths,
    this.previousAmount,
    this.previousPriceUnit,
    this.newLeaseEnd,
  });

  final int amount;
  final String priceUnit;
  final int leaseMonths;
  final int? previousAmount;
  final String? previousPriceUnit;
  final DateTime? newLeaseEnd;

  /// True when renewing costs more than the tenant paid last time.
  bool get isIncrease => previousAmount != null && previousPriceUnit == priceUnit && amount > previousAmount!;

  factory RenewalQuote.fromApi(Map<String, dynamic> json) => RenewalQuote(
    amount: json['amount'] as int,
    priceUnit: json['priceUnit'] as String,
    leaseMonths: json['leaseMonths'] as int,
    previousAmount: json['previousAmount'] as int?,
    previousPriceUnit: json['previousPriceUnit'] as String?,
    newLeaseEnd: json['newLeaseEnd'] == null ? null : DateTime.parse(json['newLeaseEnd'] as String).toLocal(),
  );
}

/// `POST /bookings`'s response — for a non-Shortlet property this now
/// charges immediately, so the booking row and the charge result come back
/// merged in the same response (`{...booking, reference, authorizationUrl}`).
/// [payment] is null for a Shortlet booking (no immediate charge — the
/// landlord must `respond` first, then `pay` is called separately).
class BookingCreationResult {
  const BookingCreationResult({required this.booking, this.payment});

  final Booking booking;
  final PaymentInitiation? payment;
}

class BookingsRepository {
  BookingsRepository(this._client);

  final ApiClient _client;

  /// [nights]/[requestedDate] are only ever sent when [isShortlet] — for a
  /// non-Shortlet property the inspection date is decided later, via
  /// [proposeInspection], not at creation time.
  Future<BookingCreationResult> create({
    required String propertyId,
    required bool isShortlet,
    DateTime? requestedDate,
    String? message,
    int? nights,
    bool payMonthly = false,
  }) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/bookings',
        data: {
          'propertyId': propertyId,
          if (isShortlet && requestedDate != null) 'requestedDate': requestedDate.toUtc().toIso8601String(),
          if (message != null && message.isNotEmpty) 'message': message,
          if (isShortlet && nights != null) 'nights': nights,
          if (!isShortlet && payMonthly) 'paymentPlan': 'MONTHLY',
        },
      );
      final data = response.data as Map<String, dynamic>;
      final booking = Booking.fromApi(data);
      final authorizationUrl = data['authorizationUrl'] as String?;
      final reference = data['reference'] as String?;
      final payment = (authorizationUrl != null && reference != null)
          ? PaymentInitiation(authorizationUrl: authorizationUrl, reference: reference)
          : null;
      return BookingCreationResult(booking: booking, payment: payment);
    });
  }

  Future<List<Booking>> mine() {
    return _client.call(() async {
      final response = await _client.dio.get('/bookings/mine');
      return (response.data as List).cast<Map<String, dynamic>>().map(Booking.fromApi).toList();
    });
  }

  Future<List<Booking>> forLandlord() {
    return _client.call(() async {
      final response = await _client.dio.get('/bookings/landlord');
      return (response.data as List).cast<Map<String, dynamic>>().map(Booking.fromApi).toList();
    });
  }

  /// Shortlet-only now — the landlord's accept/decline of the booking
  /// itself before the tenant pays. A non-Shortlet booking never sits
  /// PENDING waiting on this; its equivalents are [respondToInspection]
  /// and [rejectBooking].
  Future<void> respond({required String id, required bool accepted}) {
    return _client.call(() async {
      await _client.dio.patch('/bookings/$id/respond', data: {'accepted': accepted});
    });
  }

  /// Starts a Paystack charge for this booking — open [PaymentInitiation.authorizationUrl]
  /// in a browser/webview; the booking flips to PAID (Shortlet) or
  /// PAID_AWAITING_INSPECTION (non-Shortlet) once the webhook lands. Also
  /// usable as a retry if a create-time charge attempt didn't finish.
  Future<PaymentInitiation> pay(String id) {
    return _client.call(() async {
      final response = await _client.dio.post('/bookings/$id/pay');
      return PaymentInitiation.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Called when Paystack sends the tenant back to the app with this
  /// [reference]: the server checks the charge with Paystack and, if it
  /// went through, marks the booking paid straight away instead of waiting
  /// on the webhook. True if it's paid.
  Future<bool> confirmPayment(String reference) {
    return _client.call(() async {
      final response = await _client.dio.post('/bookings/confirm-payment', data: {'reference': reference});
      return (response.data as Map<String, dynamic>)['paid'] as bool? ?? false;
    });
  }

  // The six booking actions below return nothing: the server replies with
  // the bare booking row (no property or tenant attached), which
  // Booking.fromApi can't read. AppState reloads the list after each one
  // instead. (Parsing that reply would throw after the action had already
  // succeeded, leaving the screen stale.)
  /// Tenant proposes (or re-proposes, after a decline) an inspection date —
  /// only valid while the booking is PAID_AWAITING_INSPECTION, including
  /// much later than payment ("book later").
  Future<void> proposeInspection({required String id, required DateTime requestedDate}) {
    return _client.call(() async {
      await _client.dio.post(
        '/bookings/$id/inspection',
        data: {'requestedDate': requestedDate.toUtc().toIso8601String()},
      );
    });
  }

  /// Landlord accepts/declines the tenant's specific proposed inspection
  /// date — distinct from [rejectBooking], which ends the booking outright.
  Future<void> respondToInspection({required String id, required bool accepted}) {
    return _client.call(() async {
      await _client.dio.patch('/bookings/$id/inspection/respond', data: {'accepted': accepted});
    });
  }

  /// Landlord sets (or changes) the inspection date themselves — whether or
  /// not the tenant has proposed one. Confirms it straight away.
  Future<void> scheduleInspection({required String id, required DateTime date}) {
    return _client.call(() async {
      await _client.dio.post('/bookings/$id/inspection/schedule', data: {'requestedDate': date.toUtc().toIso8601String()});
    });
  }

  /// Landlord's distinct "reject this booking outright" lever — valid from
  /// any pre-move-in, post-payment state. Full refund, no platform fee
  /// withheld (contrast with the tenant's own [refund], which keeps a 0.2%
  /// cut).
  Future<void> rejectBooking(String id) {
    return _client.call(() async {
      await _client.dio.post('/bookings/$id/reject');
    });
  }

  /// Releases the held payment to the landlord and generates the persisted
  /// tenancy agreement.
  Future<void> markMovedIn(String id) {
    return _client.call(() async {
      await _client.dio.post('/bookings/$id/moved-in');
    });
  }

  /// Refunds the tenant (minus fees) — only valid before "moved in".
  Future<void> refund(String id) {
    return _client.call(() async {
      await _client.dio.post('/bookings/$id/refund');
    });
  }

  /// Renews an active lease before it expires.
  /// Exactly what renewing would charge right now, and what was paid last
  /// time — shown to the tenant before they confirm.
  Future<RenewalQuote> renewalQuote(String id) {
    return _client.call(() async {
      final response = await _client.dio.get('/bookings/$id/renewal-quote');
      return RenewalQuote.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Starts the renewal charge — open [PaymentInitiation.authorizationUrl].
  /// [quote] is what the tenant agreed to; if the landlord changed the rent
  /// or lease length since, the server refuses (409) and nothing is charged.
  Future<PaymentInitiation> renew(String id, RenewalQuote quote) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/bookings/$id/renew',
        data: {'expectedAmount': quote.amount, 'expectedLeaseMonths': quote.leaseMonths},
      );
      return PaymentInitiation.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Monthly plan: starts the charge for next month's rent — open the
  /// returned checkout. The server allows it from 7 days before it's due.
  Future<PaymentInitiation> payNextMonth(String id) {
    return _client.call(() async {
      final response = await _client.dio.post('/bookings/$id/pay-month');
      return PaymentInitiation.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Null if no tenancy agreement has been generated for this booking yet
  /// (404 before move-in).
  Future<TenancyAgreement?> tenancyAgreement(String id) async {
    try {
      return await _client.call(() async {
        final response = await _client.dio.get('/bookings/$id/tenancy-agreement');
        final data = response.data;
        if (data == null) return null;
        return TenancyAgreement.fromApi(data as Map<String, dynamic>);
      });
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Clear requests from the landlord's dashboard feed, or put them back
  /// ([cleared] false, for Undo). No [bookingIds] = every pending request.
  Future<void> setFeedCleared({required bool cleared, List<String>? bookingIds}) => _client.call(() async {
    await _client.dio.patch('/bookings/landlord/feed', data: {'cleared': cleared, if (bookingIds != null) 'bookingIds': bookingIds});
  });
}
