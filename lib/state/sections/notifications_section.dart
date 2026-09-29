part of '../app_state.dart';

/// The notification bell's list and unread count, and this browser's Web
/// Push subscription.
mixin _NotificationsSection on ChangeNotifier {
  String? get userId;
  PushRepository get _pushRepo;
  NotificationsRepository get _notificationsRepo;

  // --- Web Push ------------------------------------------------------------

  /// Keeps this browser's push subscription registered for the signed-in
  /// user. Does nothing unless notifications are already allowed and the
  /// server has push configured — asking for permission is [enableWebPush]'s
  /// job, from a tap.
  Future<void> syncWebPush() async {
    if (!webPushSupported || browserNotificationPermission != 'granted' || userId == null) return;
    try {
      final key = await _pushRepo.publicKey();
      if (key == null) return;
      final subscription = await subscribeWebPush(key);
      if (subscription != null) await _pushRepo.subscribe(subscription);
    } catch (_) {
      // Best-effort: the in-app banners still work without push.
    }
  }

  /// From a user tap: asks the browser for notification permission, then
  /// registers for push. Returns whether notifications are now allowed.
  Future<bool> enableWebPush() async {
    final permission = await requestBrowserNotificationPermission();
    if (permission != 'granted') return false;
    await syncWebPush();
    return true;
  }

  Future<void> _forgetWebPush() async {
    try {
      final endpoint = await unsubscribeWebPush();
      if (endpoint != null) await _pushRepo.unsubscribe(endpoint);
    } catch (_) {}
  }

  // --- Notifications -----------------------------------------------------

  List<AppNotification> notifications = [];
  int unreadNotificationCount = 0;

  Future<void> loadNotifications() async {
    try {
      final results = await Future.wait([_notificationsRepo.findMine(), _notificationsRepo.unreadCount()]);
      notifications = results[0] as List<AppNotification>;
      unreadNotificationCount = results[1] as int;
      notifyListeners();
    } catch (_) {
      // Leaves whatever was last loaded (or the empty default) in place —
      // the bell/list just won't reflect anything newer until the next
      // successful load.
    }
  }

  Future<void> markNotificationRead(String id) async {
    final index = notifications.indexWhere((n) => n.id == id);
    if (index == -1 || notifications[index].isRead) return;
    await _notificationsRepo.markRead(id);
    notifications[index] = notifications[index].markedRead();
    unreadNotificationCount = (unreadNotificationCount - 1).clamp(0, 1 << 30);
    notifyListeners();
  }

  /// The server clears a conversation's notifications when it's read
  /// (ChatService.markRead); this mirrors that locally so the bell count
  /// drops straight away.
  void _markThreadNotificationsReadLocally(String threadId) {
    final cleared = notifications.where((n) => n.threadId == threadId && !n.isRead).length;
    if (cleared == 0) return;
    notifications = [for (final n in notifications) n.threadId == threadId ? n.markedRead() : n];
    unreadNotificationCount = (unreadNotificationCount - cleared).clamp(0, 1 << 30);
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    if (unreadNotificationCount == 0) return;
    await _notificationsRepo.markAllRead();
    notifications = [
      for (final n in notifications)
        n.markedRead(),
    ];
    unreadNotificationCount = 0;
    notifyListeners();
  }

  /// Called on logout.
  void _clearNotifications() {
    notifications = [];
    unreadNotificationCount = 0;
  }
}
