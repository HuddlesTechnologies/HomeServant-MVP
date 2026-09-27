// Browser pop-up notifications for the admin console on web — see
// browser_notifications_web.dart. No-ops everywhere else.
export 'browser_notifications_stub.dart' if (dart.library.html) 'browser_notifications_web.dart';
