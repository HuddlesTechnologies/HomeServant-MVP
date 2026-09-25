import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/app_notification.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';

/// The vendor-relevant subset of this account's notifications — the same
/// underlying rows the tenant-facing bell/[NotificationsScreen] show (see
/// `NotificationsRepository.findMine()`/`AppState.notifications`), filtered
/// client-side to the types a vendor cares about. Reached from the bell
/// icon on the vendor dashboard.
const _vendorNotificationTypes = {
  NotificationType.vendorApproved,
  NotificationType.vendorRejected,
  NotificationType.vendorSuspended,
  NotificationType.vendorUnsuspended,
  NotificationType.marketplaceOrderStatus,
};

IconData _iconForType(NotificationType type) => switch (type) {
  NotificationType.vendorApproved || NotificationType.vendorUnsuspended => Icons.storefront_rounded,
  NotificationType.vendorRejected || NotificationType.vendorSuspended => Icons.storefront_outlined,
  NotificationType.marketplaceOrderStatus => Icons.local_shipping_rounded,
  _ => Icons.notifications_rounded,
};

class VendorNotificationsScreen extends StatefulWidget {
  const VendorNotificationsScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<VendorNotificationsScreen> createState() => _VendorNotificationsScreenState();
}

class _VendorNotificationsScreenState extends State<VendorNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().loadNotifications();
  }

  List<AppNotification> _vendorNotifications(AppState appState) =>
      appState.notifications.where((n) => _vendorNotificationTypes.contains(n.type)).toList();

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final appState = context.watch<AppState>();
    final notifications = _vendorNotifications(appState);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Notifications', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
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
      ),
      body: SafeArea(
        child: notifications.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    "Updates about your shop — approvals, orders and more — will show up here.",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () => context.read<AppState>().loadNotifications(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = notifications[index];
                    final unread = !item.isRead;
                    return GestureDetector(
                      onTap: () => context.read<AppState>().markNotificationRead(item.id),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(18)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: theme.accent.withValues(alpha: 0.15),
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
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.body(
                                            color: theme.onSurface,
                                            size: 14,
                                            weight: unread ? FontWeight.w800 : FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        formatRelativeTime(item.createdAt),
                                        style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.5), size: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.body,
                                    style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 12.5),
                                  ),
                                ],
                              ),
                            ),
                            if (unread)
                              Container(
                                width: 9,
                                height: 9,
                                margin: const EdgeInsets.only(left: 8, top: 6),
                                decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
