import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../state/app_state.dart';

/// Shared by every admin tab that shows a moderation action (delete a
/// user, approve/reject/suspend a vendor, remove a listing) — those all
/// require at least MODERATOR server-side (AdminLevelGuard); this just
/// keeps a SUPPORT-level admin from seeing a button that would 403 if
/// tapped.
///
/// Uses `watch`, not `select`: these getters are called straight from list
/// item builders (Users, Vendors, Properties, Marketplace), and provider
/// asserts that `select` is never used there — in debug builds that
/// assertion replaced each of those lists with the red error screen.
extension AdminPermissions on BuildContext {
  bool get canModerate => watch<AppState>().adminLevel?.atLeastModerator ?? false;

  /// Gates the Activity Log's "Clear" action — every admin can view the
  /// log, only a SUPER_ADMIN can wipe any of it (server-enforced too, see
  /// AdminController.clearActivityLog).
  bool get isSuperAdmin => watch<AppState>().adminLevel?.isSuperAdmin ?? false;
}
