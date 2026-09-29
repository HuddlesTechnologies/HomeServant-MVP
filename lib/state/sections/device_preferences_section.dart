part of '../app_state.dart';

/// Settings kept on this device only, with no server copy: the dashboard
/// theme, notification toggles, and the app-lock PIN (itself stored in the
/// keychain via [TokenStorage]). Saved by AppState's [_save].
mixin _DevicePreferencesSection on ChangeNotifier {
  TokenStorage get _tokens;

  DashboardTheme dashboardTheme = DashboardTheme.classic;

  // --- Notification preferences (device-local, no server model) ----------

  bool pushNotificationsEnabled = true;
  bool newMessageNotifications = true;
  bool propertyUpdateNotifications = true;
  // Ties directly into the Wishlist feature — lets a tenant know the moment
  // a house they've saved gets cheaper, without having to keep re-checking it.
  bool wishlistPriceDropAlerts = true;
  bool promotionalNotifications = false;

  void setPushNotificationsEnabled(bool value) {
    pushNotificationsEnabled = value;
    notifyListeners();
  }

  void setNewMessageNotifications(bool value) {
    newMessageNotifications = value;
    notifyListeners();
  }

  void setPropertyUpdateNotifications(bool value) {
    propertyUpdateNotifications = value;
    notifyListeners();
  }

  void setWishlistPriceDropAlerts(bool value) {
    wishlistPriceDropAlerts = value;
    notifyListeners();
  }

  void setPromotionalNotifications(bool value) {
    promotionalNotifications = value;
    notifyListeners();
  }

  /// Controls the global Instagram-style banner shown by
  /// NotificationBannerOverlay the instant a `notification:new` socket
  /// event arrives: `true` (default) auto-dismisses it after ~3s; `false`
  /// leaves it up until the user swipes it away. Purely a display
  /// preference (no server model), same as the rest of this section.
  bool bannerAutoDismiss = true;

  void setBannerAutoDismiss(bool value) {
    bannerAutoDismiss = value;
    notifyListeners();
  }

  // --- Security: app lock (device-local) ----------------------------------

  bool appLockEnabled = false;
  String? appLockPin;

  void enableAppLock(String pin) {
    appLockEnabled = true;
    appLockPin = pin;
    unawaited(_tokens.saveAppLockPin(pin));
    notifyListeners();
  }

  void disableAppLock() {
    appLockEnabled = false;
    appLockPin = null;
    unawaited(_tokens.clearAppLockPin());
    notifyListeners();
  }

  void setDashboardTheme(DashboardTheme theme) {
    dashboardTheme = theme;
    notifyListeners();
    AppIconService.apply(theme);
  }

  /// Called on logout: back to the defaults, and the PIN removed from the
  /// keychain.
  void _clearDevicePreferences() {
    pushNotificationsEnabled = true;
    newMessageNotifications = true;
    propertyUpdateNotifications = true;
    wishlistPriceDropAlerts = true;
    promotionalNotifications = false;
    bannerAutoDismiss = true;
    appLockEnabled = false;
    appLockPin = null;
    unawaited(_tokens.clearAppLockPin());
    dashboardTheme = DashboardTheme.classic;
  }
}
