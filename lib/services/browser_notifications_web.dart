// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
// Only reaches the web build via the `dart.library.html` conditional import
// in browser_notifications.dart — same pattern as web_session_storage_web.dart.
import 'dart:async';
import 'dart:convert';
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

// --- Web Push -----------------------------------------------------------
// Unlike the pop-ups above, these reach the user when the site isn't open:
// a service worker (web/push-sw.js) receives pushes from the backend
// (PushService) and shows them. Everything goes through js_util so it
// doesn't depend on dart:html's partial service-worker bindings.

const _pushScope = './push/';

bool get webPushSupported =>
    js_util.hasProperty(html.window.navigator, 'serviceWorker') && js_util.hasProperty(html.window, 'PushManager');

Object get _serviceWorkers => js_util.getProperty<Object>(html.window.navigator, 'serviceWorker');

/// Registers the push worker and waits for it to be active (it controls
/// no page, so `navigator.serviceWorker.ready` would never resolve).
Future<Object> _activeRegistration() async {
  final registration = await js_util.promiseToFuture<Object>(
    js_util.callMethod(_serviceWorkers, 'register', ['push-sw.js', js_util.jsify({'scope': _pushScope})]),
  );
  for (var i = 0; i < 100 && js_util.getProperty<Object?>(registration, 'active') == null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return registration;
}

Map<String, dynamic> _subscriptionJson(Object subscription) {
  final json = js_util.getProperty<Object>(html.window, 'JSON');
  final text = js_util.callMethod<String>(json, 'stringify', [subscription]);
  return jsonDecode(text) as Map<String, dynamic>;
}

/// Subscribes this browser to push (permission must already be granted)
/// and returns the subscription as `{endpoint, keys: {p256dh, auth}}`, or
/// null if the browser can't. Reuses an existing subscription, replacing
/// it if it was made with a different server key.
Future<Map<String, dynamic>?> subscribeWebPush(String vapidPublicKey) async {
  if (!webPushSupported || browserNotificationPermission != 'granted') return null;
  try {
    final registration = await _activeRegistration();
    final pushManager = js_util.getProperty<Object>(registration, 'pushManager');
    final options = js_util.jsify({'userVisibleOnly': true, 'applicationServerKey': vapidPublicKey});
    final existing = await js_util.promiseToFuture<Object?>(js_util.callMethod(pushManager, 'getSubscription', const []));
    if (existing != null) {
      try {
        return _subscriptionJson(existing);
      } catch (_) {
        await js_util.promiseToFuture<Object?>(js_util.callMethod(existing, 'unsubscribe', const []));
      }
    }
    try {
      final subscription = await js_util.promiseToFuture<Object>(js_util.callMethod(pushManager, 'subscribe', [options]));
      return _subscriptionJson(subscription);
    } catch (_) {
      // Most often: an old subscription made with a different key. Drop it
      // and try once more.
      final stale = await js_util.promiseToFuture<Object?>(js_util.callMethod(pushManager, 'getSubscription', const []));
      if (stale == null) return null;
      await js_util.promiseToFuture<Object?>(js_util.callMethod(stale, 'unsubscribe', const []));
      final subscription = await js_util.promiseToFuture<Object>(js_util.callMethod(pushManager, 'subscribe', [options]));
      return _subscriptionJson(subscription);
    }
  } catch (_) {
    return null;
  }
}

/// Unsubscribes this browser (on sign-out) and returns the endpoint that
/// was removed, so the server can forget it too.
Future<String?> unsubscribeWebPush() async {
  if (!webPushSupported) return null;
  try {
    final registration = await js_util.promiseToFuture<Object?>(
      js_util.callMethod(_serviceWorkers, 'getRegistration', [_pushScope]),
    );
    if (registration == null) return null;
    final pushManager = js_util.getProperty<Object>(registration, 'pushManager');
    final subscription = await js_util.promiseToFuture<Object?>(js_util.callMethod(pushManager, 'getSubscription', const []));
    if (subscription == null) return null;
    final endpoint = js_util.getProperty<String>(subscription, 'endpoint');
    await js_util.promiseToFuture<Object?>(js_util.callMethod(subscription, 'unsubscribe', const []));
    return endpoint;
  } catch (_) {
    return null;
  }
}
