import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../api/models/admin_models.dart';
import '../../../state/app_state.dart';

/// Shared by every admin tab that shows a moderation action (delete a
/// user, approve/reject/suspend a vendor, remove a listing) — those all
/// require at least MODERATOR server-side (AdminLevelGuard); this just
/// keeps a SUPPORT-level admin from seeing a button that would 403 if
/// tapped. Selects just [AppState.adminLevel] so this only rebuilds when
/// that one field changes, rather than on every AppState change.
extension AdminPermissions on BuildContext {
  bool get canModerate => (select<AppState, AdminLevel?>((s) => s.adminLevel)?.atLeastModerator) ?? false;

  /// Gates the Activity Log's "Clear" action — every admin can view the
  /// log, only a SUPER_ADMIN can wipe any of it (server-enforced too, see
  /// AdminController.clearActivityLog).
  bool get isSuperAdmin => (select<AppState, AdminLevel?>((s) => s.adminLevel)?.isSuperAdmin) ?? false;
}
