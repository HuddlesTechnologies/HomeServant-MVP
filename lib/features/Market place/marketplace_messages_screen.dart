import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/chat.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../services/chat_socket_service.dart';
import '../../state/app_state.dart';
import '../../widgets/chat_thread_list_tile.dart';
import '../dashboard/chat_thread_screen.dart';

/// A customer's conversations with vendors — every thread tied to a
/// marketplace order (`thread.orderId != null`), same live list the
/// dashboard's own Messages tab draws from (see MessagesScreen), just
/// filtered down to the marketplace ones so a tenant who's also a
/// customer sees the two inboxes as separate, purpose-scoped views
/// rather than two unrelated features. Starting a *new* vendor
/// conversation still happens from order history/an order's detail
/// screen (see OrderHistoryScreen/VendorOrderDetailScreen) — this screen
/// is only the inbox of ones already begun.
class MarketplaceMessagesScreen extends StatefulWidget {
  const MarketplaceMessagesScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<MarketplaceMessagesScreen> createState() => _MarketplaceMessagesScreenState();
}

class _MarketplaceMessagesScreenState extends State<MarketplaceMessagesScreen> {
  List<ChatThread>? _threads;
  StreamSubscription<ChatSocketMessage>? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _socketSubscription = context.read<AppState>().chatSocket.onNewMessage.listen((_) => _load());
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final threads = await context.read<AppState>().chat.myThreads();
      if (!mounted) return;
      setState(() => _threads = threads.where((t) => t.orderId != null).toList());
    } catch (_) {
      if (!mounted) return;
      setState(() => _threads = []);
    }
  }

  Future<void> _openThread(ChatThread thread) async {
    final theme = widget.theme;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          theme: theme,
          contactName: thread.otherParticipantName,
          threadId: thread.id,
          otherParticipant: thread.otherParticipant,
        ),
      ),
    );
    if (!mounted) return;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final threads = _threads;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Messages', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: threads == null
              ? const Center(child: CircularProgressIndicator())
              : threads.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      "You can message a vendor once you've bought a pickup item from them.",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    itemCount: threads.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      final unread = thread.unreadCount > 0;
                      return GestureDetector(
                        onTap: () => _openThread(thread),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(18)),
                          child: ChatThreadListTile(
                            thread: thread,
                            avatar: CircleAvatar(
                              radius: 24,
                              backgroundColor: theme.accent.withValues(alpha: 0.25),
                              child: Icon(Icons.storefront_rounded, color: theme.accent),
                            ),
                            nameStyle: AppTextStyles.body(
                              color: theme.onSurface,
                              size: 14,
                              weight: unread ? FontWeight.w800 : FontWeight.w700,
                            ),
                            messageStyle: AppTextStyles.body(
                              color: theme.onSurface.withValues(alpha: unread ? 0.9 : 0.6),
                              size: 13,
                              weight: unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                            trailing: unread
                                ? Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                                  )
                                : null,
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
