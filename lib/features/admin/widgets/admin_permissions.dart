import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../../../state/app_state.dart';

/// Shared by every admin tab that shows a moderation action (delete a
/// user, approve/reject/suspend a vendor, remove a listing) — those all
/// require at least MODERATOR server-side (AdminLevelGuard); this just
/// keeps a SUPPORT-level admin from seeing a button that would 403 if
/// tapped. Watches AppState so the UI updates live if this admin's own
/// level is ever changed mid-session.
extension AdminPermissions on BuildContext {
  bool get canModerate => watch<AppState>().adminLevel?.atLeastModerator ?? false;
}
