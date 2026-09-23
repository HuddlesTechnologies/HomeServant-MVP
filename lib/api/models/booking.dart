import '../../features/dashboard/models/property.dart';

enum BookingStatus { pending, accepted, declined }

BookingStatus _statusFromApi(String value) => switch (value) {
  'ACCEPTED' => BookingStatus.accepted,
  'DECLINED' => BookingStatus.declined,
  _ => BookingStatus.pending,
};

/// Mirrors a `Booking` row from `GET /bookings/mine` / `GET
/// /bookings/landlord` (see backend/src/bookings/bookings.service.ts),
/// with its related [Property] embedded the same way the API includes it.
class Booking {
  const Booking({
    required this.id,
    required this.property,
    required this.status,
    required this.createdAt,
    this.tenantId,
    this.tenantName,
    this.requestedDate,
    this.message,
  });

  final String id;
  final Property property;
  final BookingStatus status;
  final DateTime createdAt;
  final String? tenantId;
  final String? tenantName;
  final DateTime? requestedDate;
  final String? message;

  factory Booking.fromApi(Map<String, dynamic> json) {
    final tenant = json['tenant'] as Map<String, dynamic>?;
    return Booking(
      id: json['id'] as String,
      property: Property.fromApi(json['property'] as Map<String, dynamic>),
      status: _statusFromApi(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      tenantId: tenant?['id'] as String? ?? json['tenantId'] as String?,
      tenantName: tenant?['fullName'] as String?,
      requestedDate: (json['requestedDate'] as String?) != null ? DateTime.parse(json['requestedDate'] as String) : null,
      message: json['message'] as String?,
    );
  }
}
