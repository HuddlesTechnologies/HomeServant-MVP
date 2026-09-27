import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/app_notification.dart';
import '../../api/models/chat.dart';
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/dashboard_page_scaffold.dart';
import '../../widgets/empty_state.dart';
import '../admin/widgets/support_thread_actions.dart';
import 'chat_thread_screen.dart';

IconData _iconForType(NotificationType type) => switch (type) {
  NotificationType.referralSignup => Icons.card_giftcard_rounded,
  NotificationType.vendorApproved => Icons.storefront_rounded,
  NotificationType.vendorRejected => Icons.storefront_outlined,
  NotificationType.vendorSuspended => Icons.storefront_outlined,
  NotificationType.vendorUnsuspended => Icons.storefront_rounded,
  NotificationType.bookingStatus => Icons.event_available_rounded,
  NotificationType.marketplaceOrderStatus => Icons.local_shipping_rounded,
  NotificationType.newMessage => Icons.chat_bubble_rounded,
  NotificationType.reportAssigned => Icons.flag_rounded,
  NotificationType.threadTransferred => Icons.forward_to_inbox_rounded,
  NotificationType.rentExpiryReminder => Icons.event_busy_rounded,
  NotificationType.newListingMessage => Icons.chat_bubble_outline_rounded,
  NotificationType.supportThreadResolved => Icons.check_circle_outline_rounded,
};

/// The types a vendor cares about — see [NotificationsScreen.vendorOnly].
const _vendorNotificationTypes = {
  NotificationType.vendorApproved,
  NotificationType.vendorRejected,
  NotificationType.vendorSuspended,
  NotificationType.vendorUnsuspended,
  NotificationType.marketplaceOrderStatus,
};

/// This account's notifications. With [vendorOnly] (the vendor
/// dashboard's bell) it shows just the shop-related ones — the same
/// underlying rows, filtered client-side. The vendor list used to be a
/// separate near-copy of this screen.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.theme, this.vendorOnly = false});

  final DashboardTheme theme;
  final bool vendorOnly;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final all = context.watch<AppState>().notifications;
    final notifications = widget.vendorOnly ? all.where((n) => _vendorNotificationTypes.contains(n.type)).toList() : all;
    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: 'Notifications',
      actions: [
        if (notifications.any((n) => !n.isRead))
          TextButton(
            onPressed: () => context.read<AppState>().markAllNotificationsRead(),
            child: Text(
              'Mark all read',
              style: AppTextStyles.body(color: theme.accent, weight: FontWeight.w600, size: 13),
            ),
          ),
      ],
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: notifications.isEmpty
              ? EmptyState(
                  theme: theme,
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications yet',
                  message: widget.vendorOnly
                      ? 'Updates about your shop — approvals, orders and more — will show up here.'
                      : "You'll see updates here as they happen.",
                )
              : RefreshIndicator(
                  onRefresh: () => context.read<AppState>().loadNotifications(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = notifications[index];
                      return Material(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () {
                            context.read<AppState>().markNotificationRead(item.id);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => NotificationDetailScreen(theme: theme, item: item),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.accent.withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_iconForType(item.type), color: theme.accent, size: 20),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              style: AppTextStyles.body(
                                                color: theme.onSurface,
                                                size: 15,
                                                weight: item.isRead ? FontWeight.w600 : FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            formatRelativeTime(item.createdAt),
                                            style: AppTextStyles.body(
                                              color: theme.onSurface.withValues(alpha: 0.5),
                                              size: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.body,
                                        style: AppTextStyles.body(
                                          color: theme.onSurface.withValues(alpha: 0.75),
                                          size: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!item.isRead)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8, top: 4),
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

/// Full view of a single notification, reached by tapping it in the list.
/// A single notification. For one about a chat (new message, transferred
/// conversation, resolved support chat) it also shows where that
/// conversation stands *now* — waiting for an admin, being handled by
/// someone, transferred away, or resolved — and opens it: to reply when
/// the user still can, read-only otherwise. Admins get the same
/// Resolve/Transfer actions there as from their Messages tab.
class NotificationDetailScreen extends StatefulWidget {
  const NotificationDetailScreen({super.key, required this.theme, required this.item});

  final DashboardTheme theme;
  final AppNotification item;

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  ThreadSummary? _summary;
  String? _summaryError;
  bool _loadingSummary = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.threadId != null) _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loadingSummary = true;
      _summaryError = null;
    });
    try {
      final summary = await context.read<AppState>().chat.summary(widget.item.threadId!);
      if (!mounted) return;
      setState(() => _summary = summary);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _summaryError = e.message);
    } finally {
      if (mounted) setState(() => _loadingSummary = false);
    }
  }

  /// One line describing the conversation's current state.
  String _statusText(ThreadSummary summary, String? myId) {
    if (summary.resolved) {
      final when = summary.resolvedAt != null ? ' ${formatRelativeTime(summary.resolvedAt!)}' : '';
      return 'This conversation was resolved$when.';
    }
    final assigned = summary.assignedAdmin;
    if (summary.isSupport && assigned == null) {
      return 'Waiting for an admin. Replying will assign it to you.';
    }
    if (assigned != null && assigned.id == myId) {
      return summary.lastTransferTo?.id == myId && summary.lastTransferFrom != null
          ? 'Transferred to you by ${summary.lastTransferFrom!.displayName}. You are handling it.'
          : 'You are handling this conversation.';
    }
    if (assigned != null) {
      if (summary.lastTransferFrom?.id == myId) {
        return 'You transferred this conversation to ${assigned.displayName}.';
      }
      return summary.lastTransferTo?.id == assigned.id
          ? 'Transferred to ${assigned.displayName}, who is handling it now.'
          : '${_capitalized(assigned.displayName)} is handling this conversation.';
    }
    return summary.canReply ? 'You can reply to this conversation.' : "You can't reply to this conversation.";
  }

  static String _capitalized(String text) => text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  Future<void> _openThread(ThreadSummary summary) async {
    final appState = context.read<AppState>();
    final isAdmin = appState.role.isAdmin;
    final other = summary.otherParticipants.isNotEmpty ? summary.otherParticipants.first : null;
    final contactName = other?.fullName?.trim().isNotEmpty == true ? other!.fullName! : 'Conversation';
    final adminSupportActions = isAdmin && summary.isSupport && summary.canReply;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          // Admins see chats in the console's own theme, same as their
          // Messages tab does.
          theme: isAdmin ? DashboardTheme.midnight : widget.theme,
          contactName: contactName,
          threadId: summary.id,
          otherParticipant: other != null
              ? ThreadParticipant(id: other.id, fullName: other.fullName, profilePhotoUrl: other.profilePhotoUrl)
              : null,
          adminViewOfUserId: isAdmin ? other?.id : null,
          showExportAction: isAdmin,
          readOnly: !summary.canReply,
          showResolveTransferActions: adminSupportActions,
          isResolved: summary.resolved,
          onResolve: adminSupportActions ? () => resolveSupportThread(context, summary.id) : null,
          onTransfer: adminSupportActions ? () => transferSupportThread(context, summary.id) : null,
          onReassign: summary.canReassign
              ? () async {
                  await reassignSupportThread(context, summary.id, currentAdminId: summary.assignedAdmin?.id);
                }
              : null,
        ),
      ),
    );
    // Replying may have claimed it, or it may have been resolved or
    // transferred from inside the chat — refresh what this screen says.
    if (mounted) _loadSummary();
  }

  Widget _conversationPanel(DashboardTheme theme) {
    if (_loadingSummary && _summary == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(color: theme.accent)),
      );
    }
    final summary = _summary;
    if (summary == null) {
      return Text(
        _summaryError ?? "Couldn't load this conversation.",
        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.7), size: 13.5),
      );
    }
    final myId = context.read<AppState>().userId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // theme.surface/onSurface: a fixed light-surface/navy-text pair in
        // every DashboardTheme (see CLAUDE.md), unlike background/foreground.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Icon(
                summary.resolved ? Icons.check_circle_outline_rounded : Icons.forum_outlined,
                color: theme.onSurface,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _statusText(summary, myId),
                  style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (summary.canView) ...[
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            onPressed: () => _openThread(summary),
            icon: Icon(summary.canReply ? Icons.reply_rounded : Icons.visibility_outlined, color: theme.onAccent, size: 18),
            label: Text(
              summary.canReply ? 'Reply' : 'View conversation',
              style: AppTextStyles.button(color: theme.onAccent, size: 15),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final item = widget.item;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_iconForType(item.type), color: theme.accent, size: 26),
                ),
                const SizedBox(height: 18),
                Text(
                  item.title,
                  style: AppTextStyles.heading(color: theme.foreground, size: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  formatRelativeTime(item.createdAt),
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.5), size: 12),
                ),
                const SizedBox(height: 16),
                Text(
                  item.body,
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.85), size: 15),
                ),
                if (item.threadId != null) ...[
                  const SizedBox(height: 24),
                  _conversationPanel(theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
