import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/chat.dart';
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/chat_thread_list_tile.dart';
import '../../widgets/contact_avatar.dart';
import '../../widgets/dashboard_page_scaffold.dart';
import 'chat_thread_screen.dart';

/// A tenant's inbox. With [marketplaceOnly] it's the marketplace inbox
/// instead: only threads tied to a marketplace order (`thread.orderId !=
/// null`), with a shop avatar, so a tenant who's also a customer sees the
/// two as separate, purpose-scoped views. Starting a *new* vendor
/// conversation still happens from order history/an order's detail screen
/// (see OrderHistoryScreen/VendorOrderDetailScreen) — the marketplace
/// inbox only lists ones already begun.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.theme, this.marketplaceOnly = false});

  final DashboardTheme theme;
  final bool marketplaceOnly;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<ChatThread>? _threads;
  StreamSubscription<void>? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    // Without this, a message arriving while this screen is open (not the
    // thread itself, just the list) never updated the preview/ordering/
    // unread badge until a manual pull-to-refresh or leaving and coming
    // back — this is what "messaging isn't working" often actually was.
    _socketSubscription = context.read<AppState>().chatSocket.onThreadsChanged.listen((_) => _load());
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
      setState(() => _threads = widget.marketplaceOnly ? threads.where((t) => t.orderId != null).toList() : threads);
    } catch (_) {
      if (!mounted) return;
      setState(() => _threads = []);
    }
  }

  Future<void> _openThread(ChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChatThreadScreen(
              theme: widget.theme,
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
    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: 'Messages',
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child:
              threads == null
                  ? const Center(child: CircularProgressIndicator())
                  : threads.isEmpty
                  ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        widget.marketplaceOnly
                            ? "You can message a vendor once you've bought a pickup item from them."
                            : 'No conversations yet.',
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
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final thread = threads[index];
                        final unread = thread.unreadCount > 0;
                        return GestureDetector(
                          onTap: () => _openThread(thread),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.surface,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: ChatThreadListTile(
                              thread: thread,
                              avatar:
                                  widget.marketplaceOnly
                                      ? CircleAvatar(
                                        radius: 24,
                                        backgroundColor: theme.accent.withValues(alpha: 0.25),
                                        child: Icon(Icons.storefront_rounded, color: theme.accent),
                                      )
                                      : ContactAvatar(
                                        participant: thread.otherParticipant,
                                        radius: 24,
                                        backgroundColor: theme.accent.withValues(alpha: 0.25),
                                        iconColor: theme.accent,
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
                              time: Text(
                                formatRelativeTime(thread.updatedAt),
                                style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.5), size: 11),
                              ),
                              trailing:
                                  unread
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
