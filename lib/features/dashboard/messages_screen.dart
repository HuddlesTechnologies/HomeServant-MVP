import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/chat.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import 'chat_thread_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<ChatThread>? _threads;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final threads = await context.read<AppState>().chat.myThreads();
      if (!mounted) return;
      setState(() => _threads = threads);
    } catch (_) {
      if (!mounted) return;
      setState(() => _threads = []);
    }
  }

  Future<void> _openThread(ChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(theme: widget.theme, contactName: thread.otherParticipantName, threadId: thread.id),
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
        title: Text(
          'Messages',
          style: AppTextStyles.heading(color: theme.foreground, size: 18),
        ),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: threads == null
              ? const Center(child: CircularProgressIndicator())
              : threads.isEmpty
                  ? Center(
                      child: Text(
                        'No conversations yet.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                      ),
                    )
                  : ListView.separated(
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
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: theme.accent.withValues(alpha: 0.25),
                                  child: Icon(Icons.person, color: theme.accent),
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
                                              thread.otherParticipantName,
                                              overflow: TextOverflow.ellipsis,
                                              style: AppTextStyles.body(
                                                color: theme.onSurface,
                                                size: 14,
                                                weight: unread ? FontWeight.w800 : FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            _formatTime(thread.updatedAt),
                                            style: AppTextStyles.body(
                                              color: theme.onSurface.withValues(alpha: 0.5),
                                              size: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        thread.lastMessage?.body ?? 'No messages yet',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.body(
                                          color: theme.onSurface.withValues(alpha: unread ? 0.9 : 0.6),
                                          size: 13,
                                          weight: unread ? FontWeight.w600 : FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (unread) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
                                  ),
                                ],
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

String _formatTime(DateTime date) {
  final now = DateTime.now();
  final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
  if (isToday) {
    final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) return 'Yesterday';
  return '${date.day}/${date.month}';
}
