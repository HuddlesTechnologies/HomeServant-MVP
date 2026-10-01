import 'package:flutter_test/flutter_test.dart';
import 'package:homeservant/api/models/booking.dart';
import 'package:homeservant/api/models/chat.dart';

/// The chat summary tells each side the inspection they can arrange.
void main() {
  Map<String, dynamic> summary(Object? inspection) => {
    'id': 't1',
    'isSupport': false,
    'resolved': false,
    'canView': true,
    'canReply': true,
    'otherParticipants': const [],
    'inspection': inspection,
  };

  test("reads the tenant's proposed date", () {
    final s = ThreadSummary.fromApi(
      summary({'bookingId': 'b1', 'status': 'INSPECTION_PROPOSED', 'requestedDate': '2026-10-20T09:00:00.000Z', 'role': 'TENANT'}),
    );
    expect(s.inspection!.bookingId, 'b1');
    expect(s.inspection!.status, BookingStatus.inspectionProposed);
    expect(s.inspection!.isTenant, isTrue);
    expect(s.inspection!.requestedDate, DateTime.utc(2026, 10, 20, 9).toLocal());
  });

  test("reads the landlord's side, with no date yet", () {
    final s = ThreadSummary.fromApi(summary({'bookingId': 'b1', 'status': 'PAID_AWAITING_INSPECTION', 'requestedDate': null, 'role': 'LANDLORD'}));
    expect(s.inspection!.isTenant, isFalse);
    expect(s.inspection!.status, BookingStatus.paidAwaitingInspection);
    expect(s.inspection!.requestedDate, isNull);
  });

  test('no inspection to arrange', () {
    expect(ThreadSummary.fromApi(summary(null)).inspection, isNull);
  });
}
