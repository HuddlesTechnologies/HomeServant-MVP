import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a Paystack checkout page.
///
/// On web the checkout replaces the current tab instead of opening a new
/// one: the URL only exists after an API round-trip, and by then the tap
/// that started it no longer counts as a user gesture, so browsers (iOS
/// Safari especially) silently block a new window — url_launcher still
/// reports success because it opens with `noopener`, so "Rent Now" looked
/// like it did nothing. A same-tab navigation is never blocked; the
/// backend passes Paystack a `callback_url` that brings the tenant back to
/// the app afterwards, and the session survives because it lives in this
/// tab's sessionStorage.
Future<bool> openPaymentPage(String authorizationUrl) {
  final uri = Uri.parse(authorizationUrl);
  if (kIsWeb) {
    return launchUrl(uri, webOnlyWindowName: '_self');
  }
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
