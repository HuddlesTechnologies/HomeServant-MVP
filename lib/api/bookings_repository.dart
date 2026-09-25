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
  }) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/bookings',
        data: {
          'propertyId': propertyId,
          if (isShortlet && requestedDate != null) 'requestedDate': requestedDate.toIso8601String(),
          if (message != null && message.isNotEmpty) 'message': message,
          if (isShortlet && nights != null) 'nights': nights,
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
  Future<Booking> respond({required String id, required bool accepted}) {
    return _client.call(() async {
      final response = await _client.dio.patch('/bookings/$id/respond', data: {'accepted': accepted});
      return Booking.fromApi(response.data as Map<String, dynamic>);
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

  /// Tenant proposes (or re-proposes, after a decline) an inspection date —
  /// only valid while the booking is PAID_AWAITING_INSPECTION, including
  /// much later than payment ("book later").
  Future<Booking> proposeInspection({required String id, required DateTime requestedDate}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/bookings/$id/inspection',
        data: {'requestedDate': requestedDate.toIso8601String()},
      );
      return Booking.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Landlord accepts/declines the tenant's specific proposed inspection
  /// date — distinct from [rejectBooking], which ends the booking outright.
  Future<Booking> respondToInspection({required String id, required bool accepted}) {
    return _client.call(() async {
      final response = await _client.dio.patch('/bookings/$id/inspection/respond', data: {'accepted': accepted});
      return Booking.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Landlord's distinct "reject this booking outright" lever — valid from
  /// any pre-move-in, post-payment state. Full refund, no platform fee
  /// withheld (contrast with the tenant's own [refund], which keeps a 0.2%
  /// cut).
  Future<Booking> rejectBooking(String id) {
    return _client.call(() async {
      final response = await _client.dio.post('/bookings/$id/reject');
      return Booking.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Releases the held payment to the landlord and generates the persisted
  /// tenancy agreement.
  Future<Booking> markMovedIn(String id) {
    return _client.call(() async {
      final response = await _client.dio.post('/bookings/$id/moved-in');
      return Booking.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Refunds the tenant (minus fees) — only valid before "moved in".
  Future<Booking> refund(String id) {
    return _client.call(() async {
      final response = await _client.dio.post('/bookings/$id/refund');
      return Booking.fromApi(response.data as Map<String, dynamic>);
    });
  }

  /// Renews an active lease before it expires.
  Future<Booking> renew(String id) {
    return _client.call(() async {
      final response = await _client.dio.post('/bookings/$id/renew');
      return Booking.fromApi(response.data as Map<String, dynamic>);
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
}
