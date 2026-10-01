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
}
