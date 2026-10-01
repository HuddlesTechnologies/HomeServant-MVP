import 'package:flutter_test/flutter_test.dart';
import 'package:homeservant/api/models/marketplace_api.dart';

/// A marketplace item is only shown as paid once the server's payment is
/// PAID_HELD or RELEASED; a pending or failed checkout never is.
void main() {
  MarketplaceOrderItemApi item(Map<String, dynamic>? payment) => MarketplaceOrderItemApi.fromApi({
    'id': 'i1',
    'orderId': 'o1',
    'productId': 'p1',
    'vendorId': 'v1',
    'productName': 'Chair',
    'unitPrice': 10000,
    'quantity': 1,
    'fulfillment': 'DELIVERY',
    'status': 'PENDING',
    'payment': payment,
  });

  test('a pending checkout is awaiting payment, not paid or held', () {
    final pending = item({'status': 'INITIATED'});
    expect(pending.progressLabel, 'Awaiting Payment');
    expect(pending.isPaid, isFalse);
    expect(pending.isPaymentHeld, isFalse);
  });

  test('a failed payment is shown as failed, not paid or held', () {
    final failed = item({'status': 'FAILED'});
    expect(failed.progressLabel, 'Payment Failed');
    expect(failed.isPaid, isFalse);
    expect(failed.isPaymentHeld, isFalse);
  });

  test('no payment at all is not treated as held', () {
    expect(item(null).isPaymentHeld, isFalse);
    expect(item(null).isPaid, isFalse);
  });

  test('only a held or released payment counts as paid', () {
    expect(item({'status': 'PAID_HELD'}).isPaymentHeld, isTrue);
    expect(item({'status': 'PAID_HELD'}).isPaid, isTrue);
    expect(item({'status': 'RELEASED'}).isPaid, isTrue);
    expect(item({'status': 'RELEASED'}).progressLabel, 'Completed');
  });

  test('an order cancelled for not being paid says so', () {
    final cancelled = MarketplaceOrderItemApi.fromApi({
      'id': 'i1',
      'orderId': 'o1',
      'productId': 'p1',
      'vendorId': 'v1',
      'productName': 'Chair',
      'unitPrice': 10000,
      'quantity': 1,
      'fulfillment': 'DELIVERY',
      'status': 'CANCELLED',
      'payment': {'status': 'FAILED'},
    });
    expect(cancelled.progressLabel, 'Cancelled — Not Paid');
    expect(cancelled.isPaid, isFalse);
  });

  group('one checkout per order', () {
    Map<String, dynamic> order({required String paymentStatus, String? expiresAt, bool placed = false}) => {
      'id': 'o1',
      'createdAt': '2026-10-01T10:00:00.000Z',
      'paymentMethod': 'CARD',
      'customerName': 'Buyer',
      'customerPhone': '08000000000',
      'customerAddress': '1 Test Street',
      'paystackReference': 'mkto_1',
      'paymentExpiresAt': expiresAt,
      if (placed) 'checkout': {'reference': 'mkto_1', 'authorizationUrl': 'https://checkout.paystack.test/a'} else 'authorizationUrl': 'https://checkout.paystack.test/a',
      'items': [
        for (final id in ['i1', 'i2'])
          {
            'id': id,
            'orderId': 'o1',
            'productId': 'p-$id',
            'vendorId': 'v-$id',
            'productName': 'Item $id',
            'unitPrice': 5000,
            'quantity': 1,
            'fulfillment': 'DELIVERY',
            'status': 'PENDING',
            'payment': {'status': paymentStatus},
          },
      ],
    };

    test('placing an order returns its single payment page', () {
      final placed = MarketplaceOrderApi.fromApi(order(paymentStatus: 'INITIATED', placed: true));
      expect(placed.paymentUrl, 'https://checkout.paystack.test/a');
      expect(placed.paymentReference, 'mkto_1');
    });

    test('an unpaid order can be paid until it expires; a paid one cannot', () {
      final future = DateTime.now().add(const Duration(minutes: 30)).toUtc().toIso8601String();
      final past = DateTime.now().subtract(const Duration(minutes: 1)).toUtc().toIso8601String();
      expect(MarketplaceOrderApi.fromApi(order(paymentStatus: 'INITIATED', expiresAt: future)).canCompletePayment, isTrue);
      expect(MarketplaceOrderApi.fromApi(order(paymentStatus: 'INITIATED', expiresAt: past)).canCompletePayment, isFalse);
      expect(MarketplaceOrderApi.fromApi(order(paymentStatus: 'PAID_HELD', expiresAt: future)).canCompletePayment, isFalse);
    });
  });
}
