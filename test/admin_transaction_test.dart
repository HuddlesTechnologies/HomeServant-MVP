import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeservant/api/models/admin_transaction.dart';
import 'package:homeservant/features/admin/admin_transaction_detail_screen.dart';

Map<String, dynamic> _json({String status = 'RELEASED'}) => {
  'id': 'pay-1',
  'status': status,
  'amountKobo': 150000000,
  'platformFeeKobo': 7500000,
  'landlordShareKobo': 142500000,
  'reference': 'HS_ref_123',
  'payoutReference': 'po_456',
  'paidAt': '2026-09-01T10:15:00.000Z',
  'creditedAt': status == 'RELEASED' ? '2026-09-10T08:00:00.000Z' : null,
  'refundedAt': null,
  'refundReason': null,
  'heldForVerification': false,
  'tenant': {'id': 't1', 'name': 'Ada Tenant', 'email': 'ada@example.com', 'phoneNumber': '08012345678'},
  'landlord': {
    'id': 'l1',
    'name': 'Bola Landlord',
    'email': 'bola@example.com',
    'bankName': 'GTBank',
    'accountName': 'BOLA LANDLORD',
    'accountLast4': '6789',
  },
  'booking': {'id': 'b1', 'paymentPlan': 'FULL', 'nights': null, 'leaseStartDate': null, 'leaseEndDate': null},
  'property': {
    'id': 'p1',
    'listingNumber': 42,
    'title': 'Two Bedroom Flat',
    'location': 'Lekki Phase 1',
    'state': 'Lagos',
    'category': 'APARTMENT',
    'price': 1500000,
    'priceUnit': 'YEAR',
    'bedrooms': 2,
    'bathrooms': 2,
    'imageUrl': null,
    'galleryUrls': <String>[],
  },
};

void main() {
  test('parses a credited transaction', () {
    final t = AdminTransaction.fromApi(_json());
    expect(t.status, TransactionStatus.credited);
    expect(t.statusLabel, 'Credited to landlord');
    expect(t.creditedAt, isNotNull);
    expect(t.property!.listingNumber, 42);
    expect(t.landlordAccountLast4, '6789');
  });

  test('a held payment is not yet credited', () {
    final t = AdminTransaction.fromApi(_json(status: 'PAID_HELD'));
    expect(t.status, TransactionStatus.held);
    expect(t.creditedAt, isNull);
  });

  testWidgets('detail page shows the property, payment, references and both people', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AdminTransactionDetailScreen(transaction: AdminTransaction.fromApi(_json()))));
    expect(find.text('Two Bedroom Flat'), findsOneWidget);
    expect(find.text('₦1,500,000'), findsOneWidget);
    expect(find.text('HS_ref_123'), findsOneWidget);
    expect(find.text('Ada Tenant'), findsOneWidget);
    expect(find.text('GTBank ••••6789'), findsOneWidget);
    expect(find.text('View full property'), findsOneWidget);
    expect(find.text('View tenant'), findsOneWidget);
    expect(find.text('View landlord'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
