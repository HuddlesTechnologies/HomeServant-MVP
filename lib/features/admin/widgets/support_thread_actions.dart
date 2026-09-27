import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../api/api_exception.dart';
import '../../../api/models/admin_models.dart';
import '../../../state/app_state.dart';
import 'admin_picker_sheet.dart';

/// Marks a support thread resolved and confirms with a snackbar. Returns
/// whether it succeeded. Shared by the admin Messages tab and the admin
/// view of a chat notification.
Future<bool> resolveSupportThread(BuildContext context, String threadId) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<AppState>().chat.resolveThread(threadId);
    messenger.showSnackBar(const SnackBar(content: Text('Marked resolved')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Lets the admin pick another admin and hands the thread to them.
/// Returns whether a transfer happened.
Future<bool> transferSupportThread(BuildContext context, String threadId) async {
  final messenger = ScaffoldMessenger.of(context);
  final appState = context.read<AppState>();
  List<AdminAccount> admins;
  try {
    admins = await appState.admin.findAdmins();
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
  if (!context.mounted) return false;
  final myId = appState.userId;
  final chosen = await showAdminPickerSheet(
    context,
    admins: admins,
    title: 'Transfer conversation to',
    excludeAdminIds: {if (myId != null) myId},
  );
  if (chosen == null) return false;
  try {
    await appState.chat.transferThread(threadId, chosen.id);
    messenger.showSnackBar(SnackBar(content: Text('Transferred to ${chosen.email}')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Super-admin only: picks an admin and hands them this support
/// conversation, whoever is handling it now. [currentAdminId] is left out
/// of the picker. Returns whether a reassignment happened.
Future<bool> reassignSupportThread(BuildContext context, String threadId, {String? currentAdminId}) async {
  final messenger = ScaffoldMessenger.of(context);
  final appState = context.read<AppState>();
  List<AdminAccount> admins;
  try {
    admins = await appState.admin.findAdmins();
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
  if (!context.mounted) return false;
  final chosen = await showAdminPickerSheet(
    context,
    admins: admins,
    title: 'Reassign conversation to',
    excludeAdminIds: {if (currentAdminId != null) currentAdminId},
  );
  if (chosen == null) return false;
  try {
    await appState.chat.reassignThread(threadId, chosen.id);
    messenger.showSnackBar(SnackBar(content: Text('Reassigned to ${chosen.email}')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}
