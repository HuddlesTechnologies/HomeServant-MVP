// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// Only reaches the web build via the `dart.library.html` conditional import
// in browser_notifications.dart — same pattern as web_session_storage_web.dart.
import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// The browser's own Notification API (not push): works while the console
/// tab is open, even when it's in the background, minimised, or another tab
/// is in front. Nothing is sent through a server or service worker.
bool get browserNotificationsSupported => html.Notification.supported;

/// 'default' (not asked yet), 'granted' or 'denied'.
String get browserNotificationPermission =>
    browserNotificationsSupported ? (html.Notification.permission ?? 'default') : 'unsupported';

/// Must be called from a user action (a tap), or browsers ignore it.
Future<String> requestBrowserNotificationPermission() async {
  if (!browserNotificationsSupported) return 'unsupported';
  return html.Notification.requestPermission();
}

/// True when the console isn't what the admin is looking at.
bool get browserTabHidden => html.document.hidden ?? false;

void showBrowserNotification({required String title, required String body, String? tag, void Function()? onClick}) {
  if (browserNotificationPermission != 'granted') return;
  // [tag] makes a newer alert for the same conversation replace the old
  // one instead of stacking a second pop-up.
  final notification = html.Notification(title, body: body, tag: tag, icon: 'icons/Icon-192.png');
  notification.onClick.listen((_) {
    // Brings the console tab to the front (not exposed on dart:html's Window).
    js_util.callMethod<void>(html.window, 'focus', const []);
    notification.close();
    onClick?.call();
  });
}
