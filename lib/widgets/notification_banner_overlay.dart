import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/models/app_notification.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../features/dashboard/notifications_screen.dart';
import '../routes/app_router.dart';
import '../state/app_state.dart';

/// Instagram-style transient toast for any new notification (messages,
/// booking/order status, vendor approvals — everything that passes through
/// NotificationsService.create on the backend, which is the single
/// choke-point every one of those already goes through) — slides in from
/// the top the instant the `notification:new` socket event arrives, while
/// the app is open, over whatever screen happens to be showing.
///
/// Mounted globally in HomeServantApp's `MaterialApp.builder`, alongside
/// SessionExpiredGate/AppLockGate, rather than per-screen — so it isn't
/// tied to any particular route and keeps showing across navigation.
///
/// Purely additive on top of the existing unread-count badge
/// (NotificationBell) — that widget's own behaviour is untouched; this is a
/// separate, new surface reacting to the same underlying events.
class NotificationBannerOverlay extends StatefulWidget {
  const NotificationBannerOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<NotificationBannerOverlay> createState() => _NotificationBannerOverlayState();
}

class _NotificationBannerOverlayState extends State<NotificationBannerOverlay> {
  StreamSubscription<AppNotification>? _subscription;
  AppNotification? _visible;
  Timer? _dismissTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribed once — the same ChatSocketService instance (and its
    // broadcast stream) lives for AppState's whole lifetime, reconnecting
    // under the hood across login/logout rather than being replaced.
    _subscription ??= context.read<AppState>().chatSocket.onNotification.listen(_handleIncoming);
  }

  void _handleIncoming(AppNotification notification) {
    if (!mounted) return;
    final appState = context.read<AppState>();
    // Keeps the unread badge/list (NotificationBell, NotificationsScreen)
    // in sync with what the banner just showed, without this overlay
    // needing to know how those counters are maintained internally.
    unawaited(appState.loadNotifications());
    _dismissTimer?.cancel();
    setState(() => _visible = notification);
    if (appState.bannerAutoDismiss) {
      _dismissTimer = Timer(const Duration(seconds: 3), _dismiss);
    }
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    if (!mounted) return;
    setState(() => _visible = null);
  }

  /// Reuses the router's own root Navigator (see [rootNavigatorKey]) rather
  /// than this widget's own BuildContext — this overlay sits above the
  /// routed page tree (same position as SessionExpiredGate/AppLockGate),
  /// so a plain `Navigator.of(context)` here wouldn't find the app's real
  /// Navigator the way it does from inside an actual screen.
  void _openNotifications() {
    final notification = _visible;
    _dismiss();
    if (notification == null) return;
    final navigatorState = rootNavigatorKey.currentState;
    final navContext = navigatorState?.context;
    if (navigatorState == null || navContext == null) return;
    final theme = navContext.read<AppState>().dashboardTheme;
    navigatorState.push(MaterialPageRoute(builder: (_) => NotificationsScreen(theme: theme)));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notification = _visible;
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, -1.3), end: Offset.zero).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: notification == null
                  ? const SizedBox.shrink(key: ValueKey('banner-empty'))
                  : Padding(
                      key: ValueKey('banner-${notification.id}'),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      child: Dismissible(
                        key: ValueKey('banner-dismissible-${notification.id}'),
                        direction: DismissDirection.up,
                        onDismissed: (_) => _dismiss(),
                        child: _BannerCard(notification: notification, onTap: _openNotifications),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.18), shape: BoxShape.circle),
                child: const Icon(Icons.notifications_active_rounded, color: AppColors.gold, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: Colors.white, size: 14.5, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.8), size: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
