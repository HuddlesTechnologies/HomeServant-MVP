// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Paystack sends the payer back to the app with `?trxref=…&reference=…`
/// on the URL (see PaystackService's callback_url). Returns that reference,
/// once, and strips it from the address bar so a reload or bookmark doesn't
/// carry it around.
String? takePaymentReturnReference() {
  final uri = Uri.base;
  final reference = uri.queryParameters['reference'] ?? uri.queryParameters['trxref'];
  if (reference == null || reference.isEmpty) return null;
  final params = Map.of(uri.queryParameters)
    ..remove('reference')
    ..remove('trxref');
  final query = params.isEmpty ? '' : '?${Uri(queryParameters: params).query}';
  final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
  html.window.history.replaceState(null, '', '${uri.path}$query$fragment');
  return reference;
}
