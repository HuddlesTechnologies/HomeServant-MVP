import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeservant/api/models/admin_models.dart';
import 'package:homeservant/features/admin/widgets/admin_booking_history.dart';

AdminUserBooking _booking(int n) => AdminUserBooking(
  id: 'b$n',
  propertyId: 'p$n',
  propertyTitle: 'Flat $n',
  price: 1000,
  priceUnit: 'YEAR',
  status: 'MOVED_IN',
  createdAt: DateTime(2026, 1, n),
  outcome: 'Successful',
  outcomeTone: HistoryTone.success,
  timeline: [BookingTimelineEvent(at: DateTime(2026, 1, n, 9, 30), label: 'Booking requested', tone: HistoryTone.info)],
);

void main() {
  testWidgets('shows the newest three bookings first and folds the rest away', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            // Handed over oldest first on purpose — the card sorts newest first.
            child: AdminBookingHistoryCard(bookings: [for (var n = 1; n <= 5; n++) _booking(n)]),
          ),
        ),
      ),
    );

    expect(find.text('Flat 5'), findsOneWidget);
    expect(find.text('Flat 4'), findsOneWidget);
    expect(find.text('Flat 3'), findsOneWidget);
    expect(find.text('Flat 2'), findsNothing);
    expect(find.text('Flat 1'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Flat 5')).dy < tester.getTopLeft(find.text('Flat 3')).dy,
      isTrue,
      reason: 'newest at the top',
    );

    await tester.tap(find.text('Show 2 older bookings'));
    await tester.pump();
    expect(find.text('Flat 1'), findsOneWidget);

    await tester.tap(find.text('Hide older bookings'));
    await tester.pump();
    expect(find.text('Flat 1'), findsNothing);
  });

  testWidgets('a booking opens up to its timeline with dates and times', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AdminBookingHistoryCard(bookings: [_booking(7)])))),
    );
    expect(find.text('Booking requested'), findsNothing);
    await tester.tap(find.text('Flat 7'));
    await tester.pump();
    expect(find.text('Booking requested'), findsOneWidget);
    expect(find.text('7 Jan 2026, 09:30'), findsOneWidget);
  });
}
