import 'api_client.dart';
import 'models/booking.dart';

class BookingsRepository {
  BookingsRepository(this._client);

  final ApiClient _client;

  Future<Booking> create({required String propertyId, DateTime? requestedDate, String? message}) {
    return _client.call(() async {
      final response = await _client.dio.post(
        '/bookings',
        data: {
          'propertyId': propertyId,
          if (requestedDate != null) 'requestedDate': requestedDate.toIso8601String(),
          if (message != null && message.isNotEmpty) 'message': message,
        },
      );
      return Booking.fromApi(response.data as Map<String, dynamic>);
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

  Future<Booking> respond({required String id, required bool accepted}) {
    return _client.call(() async {
      final response = await _client.dio.patch('/bookings/$id/respond', data: {'accepted': accepted});
      return Booking.fromApi(response.data as Map<String, dynamic>);
    });
  }
}
