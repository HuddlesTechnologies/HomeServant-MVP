/// Non-web builds: there's no browser tab to be "in the background", so
/// these are no-ops. See browser_notifications_web.dart.
bool get browserNotificationsSupported => false;

String get browserNotificationPermission => 'unsupported';

Future<String> requestBrowserNotificationPermission() async => 'unsupported';

bool get browserTabHidden => false;

void showBrowserNotification({required String title, required String body, String? tag, void Function()? onClick}) {}

bool get webPushSupported => false;

Future<Map<String, dynamic>?> subscribeWebPush(String vapidPublicKey) async => null;

Future<String?> unsubscribeWebPush() async => null;
