import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/app_notification.dart';
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/empty_state.dart';

IconData _iconForType(NotificationType type) => switch (type) {
  NotificationType.referralSignup => Icons.card_giftcard_rounded,
  NotificationType.vendorApproved => Icons.storefront_rounded,
  NotificationType.vendorRejected => Icons.storefront_outlined,
  NotificationType.bookingStatus => Icons.event_available_rounded,
  NotificationType.marketplaceOrderStatus => Icons.local_shipping_rounded,
  NotificationType.newMessage => Icons.chat_bubble_rounded,
};

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatShortDate(time);
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.theme});

  final DashboardTheme theme;

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
    final notifications = context.watch<AppState>().notifications;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text(
          'Notifications',
          style: AppTextStyles.heading(color: theme.foreground, size: 18),
        ),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: notifications.isEmpty
              ? EmptyState(
                  theme: theme,
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications yet',
                  message: "You'll see updates here as they happen.",
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
                                            _relativeTime(item.createdAt),
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
class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({super.key, required this.theme, required this.item});

  final DashboardTheme theme;
  final AppNotification item;

  @override
  Widget build(BuildContext context) {
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
          child: Padding(
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
                  _relativeTime(item.createdAt),
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.5), size: 12),
                ),
                const SizedBox(height: 16),
                Text(
                  item.body,
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.85), size: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
