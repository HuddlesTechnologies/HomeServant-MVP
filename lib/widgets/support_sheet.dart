import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_exception.dart';
import '../api/models/support_tools.dart';
import '../core/theme/app_text_styles.dart';
import '../features/dashboard/chat_thread_screen.dart';
import '../models/dashboard_theme.dart';
import '../state/app_state.dart';

/// Home Servant's support line — shown to the user if the dialer can't be
/// launched (e.g. a browser blocking it), so they can still dial manually.
const supportPhoneNumber = '+234 700 000 0000';

/// Bottom sheet offering the two ways to reach support: a phone call or a
/// live chat thread. Shared by the tenant/landlord Settings screen and the
/// vendor Shop Profile screen so both get the same support flow.
Future<void> showSupportOptionsSheet(BuildContext context, {required DashboardTheme theme}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: theme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contact Support', style: AppTextStyles.heading(color: theme.onSurface, size: 19)),
            const SizedBox(height: 4),
            Text(
              "We're here to help — pick whichever's easiest.",
              style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 13.5),
            ),
            const SizedBox(height: 20),
            _SupportOption(
              theme: theme,
              icon: Icons.call_outlined,
              label: 'Call Support',
              subtitle: supportPhoneNumber,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _callSupport(context);
              },
            ),
            const SizedBox(height: 12),
            _SupportOption(
              theme: theme,
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Live Chat',
              subtitle: 'Chat with our support team',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _openLiveChat(context, theme);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Opens (or reuses) the caller's own support thread and pushes a real
/// [ChatThreadScreen] on it — previously this pushed a purely local,
/// scripted conversation with no `threadId`, so nothing typed here ever
/// left the device.
Future<void> _openLiveChat(BuildContext context, DashboardTheme theme) async {
  final messenger = ScaffoldMessenger.of(context);
  // What it's about routes it to the right admin and lets them triage it
  // before reading a word. Dismissing the picker cancels.
  final topic = await _pickTopic(context, theme);
  if (topic == null || !context.mounted) return;
  // Opening the conversation can take a while (a slow network, or the
  // server waking up) — show that it's working so nobody taps again and
  // again thinking nothing happened. The spinner can't be dismissed; it
  // closes itself once the chat is ready or the request fails.
  final navigator = Navigator.of(context);
  var spinnerOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(canPop: false, child: _OpeningChatDialog(theme: theme)),
    ).whenComplete(() => spinnerOpen = false),
  );
  void closeSpinner() {
    if (spinnerOpen) navigator.pop();
  }

  try {
    final threadId = await context.read<AppState>().chat.openSupportThread(topic: topic);
    closeSpinner();
    if (!context.mounted) return;
    unawaited(
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            theme: theme,
            contactName: 'HomeServant Support',
            threadId: threadId,
          ),
        ),
      ),
    );
  } on ApiException catch (e) {
    closeSpinner();
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// "Connecting you to support…" while the live chat opens.
/// theme.surface/onSurface: a fixed light-surface/navy-text pair.
class _OpeningChatDialog extends StatelessWidget {
  const _OpeningChatDialog({required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: theme.onSurface)),
            const SizedBox(width: 18),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connecting you to support…',
                    style: AppTextStyles.body(color: theme.onSurface, size: 15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This can take a few seconds.',
                    style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.65), size: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<SupportTopic?> _pickTopic(BuildContext context, DashboardTheme theme) {
  // theme.surface/onSurface: a fixed light-surface/navy-text pair.
  return showModalBottomSheet<SupportTopic>(
    context: context,
    backgroundColor: theme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What do you need help with?', style: AppTextStyles.heading(color: theme.onSurface, size: 18)),
            const SizedBox(height: 14),
            for (final topic in SupportTopic.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(topic.label, style: AppTextStyles.body(color: theme.onSurface, size: 15, weight: FontWeight.w600)),
                subtitle: Text(
                  topic.hint,
                  style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 12.5),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.5)),
                onTap: () => Navigator.of(sheetContext).pop(topic),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _callSupport(BuildContext context) async {
  final uri = Uri(scheme: 'tel', path: supportPhoneNumber.replaceAll(' ', ''));
  final launched = await canLaunchUrl(uri) && await launchUrl(uri);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Couldn't open your dialer — call us at $supportPhoneNumber")),
    );
  }
}

class _SupportOption extends StatelessWidget {
  const _SupportOption({
    required this.theme,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final DashboardTheme theme;
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: theme.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: theme.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.body(color: theme.onSurface, size: 14.5, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.55), size: 12.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }
}
