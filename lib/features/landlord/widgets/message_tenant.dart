import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../api/models/booking.dart';
import '../../../state/app_state.dart';
import '../../dashboard/chat_thread_screen.dart';

/// Landlord: opens (or starts) the chat with [booking]'s tenant about its
/// property, the same conversation their booking notices are posted in.
Future<void> messageTenant(BuildContext context, Booking booking) async {
  final appState = context.read<AppState>();
  final tenantId = booking.tenantId;
  if (tenantId == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final thread = await appState.chat.openThread(recipientId: tenantId, propertyId: booking.property.id);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          theme: appState.dashboardTheme,
          contactName: booking.tenantName?.trim().isNotEmpty == true ? booking.tenantName!.trim() : 'Tenant',
          threadId: thread.id,
          property: booking.property,
          otherParticipant: thread.otherParticipant,
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text("Couldn't open this conversation — try again.")));
  }
}
