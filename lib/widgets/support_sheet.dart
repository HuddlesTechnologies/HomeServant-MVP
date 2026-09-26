import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_exception.dart';
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
  try {
    final thread = await context.read<AppState>().chat.openSupportThread();
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          theme: theme,
          contactName: 'HomeServant Support',
          threadId: thread.id,
        ),
      ),
    );
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
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
