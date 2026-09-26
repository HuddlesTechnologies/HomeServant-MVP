import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/chat.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../services/chat_socket_service.dart';
import '../../state/app_state.dart';
import '../../widgets/chat_thread_list_tile.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/landlord_widgets.dart';

/// Messages tab of the redesigned landlord dashboard — real conversations
/// from the API, filterable by unread. "Deleted"/"Archived" have no backend
/// model yet (there's no thread-status field), so those filters always show
/// empty rather than silently keeping fake local state.
class LandlordMessagesScreen extends StatefulWidget {
  const LandlordMessagesScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<LandlordMessagesScreen> createState() => _LandlordMessagesScreenState();
}

class _LandlordMessagesScreenState extends State<LandlordMessagesScreen> {
  List<ChatThread>? _threads;
  int _filterIndex = 0;
  bool _searching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _filters = ['Unread', 'Deleted', 'Archived'];
  StreamSubscription<ChatSocketMessage>? _socketSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    _socketSubscription = context.read<AppState>().chatSocket.onNewMessage.listen((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _socketSubscription?.cancel();
    super.dispose();
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

  List<ChatThread> get _visible {
    final threads = _threads ?? const [];
    if (_searching && _searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      return threads
          .where(
            (t) =>
                t.otherParticipantName.toLowerCase().contains(query) ||
                (t.lastMessage?.body.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }
    switch (_filterIndex) {
      case 0:
        return threads.where((t) => t.unreadCount > 0).toList();
      default:
        return const [];
    }
  }

  Future<void> _openThread(ChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
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

  Future<void> _markAllRead() async {
    final appState = context.read<AppState>();
    final threads = _threads ?? const [];
    await Future.wait([for (final t in threads.where((t) => t.unreadCount > 0)) appState.chat.markRead(t.id)]);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All conversations marked as read')));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final unreadCount = (_threads ?? const []).where((t) => t.unreadCount > 0).length;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _searching
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            onChanged: (value) => setState(() => _searchQuery = value),
                            style: AppTextStyles.body(color: theme.foreground),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Search conversations',
                              hintStyle: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.5)),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: theme.foreground),
                          onPressed: () => setState(() {
                            _searching = false;
                            _searchQuery = '';
                            _searchController.clear();
                          }),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Messages', style: AppTextStyles.heading(color: theme.foreground, size: 22)),
                        Row(
                          children: [
                            InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => setState(() => _searching = true),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.search_rounded, color: theme.foreground),
                              ),
                            ),
                            const SizedBox(width: 12),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.menu_rounded, color: theme.foreground),
                              onSelected: (value) {
                                if (value == 'mark_all_read') _markAllRead();
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'mark_all_read',
                                  // The popup menu itself is always a light
                                  // Material surface regardless of theme —
                                  // theme.foreground flips to white on
                                  // Midnight and would be invisible here, so
                                  // this uses onSurface (fixed navy, paired
                                  // with a light surface in every theme).
                                  child: Text('Mark all as read', style: AppTextStyles.body(color: theme.onSurface, size: 14)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            if (!_searching || _searchQuery.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _FilterPill(
                      label: 'Unread $unreadCount',
                      selected: _filterIndex == 0,
                      onTap: () => setState(() => _filterIndex = 0),
                    ),
                    const SizedBox(width: 10),
                    _FilterPill(
                      label: 'Deleted',
                      selected: _filterIndex == 1,
                      onTap: () => setState(() => _filterIndex = 1),
                    ),
                    const SizedBox(width: 10),
                    _FilterPill(
                      label: 'Archived',
                      selected: _filterIndex == 2,
                      onTap: () => setState(() => _filterIndex = 2),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: _threads == null
                  ? const Center(child: CircularProgressIndicator())
                  : _visible.isEmpty
                      ? Center(
                          child: Text(
                            _searching && _searchQuery.trim().isNotEmpty
                                ? 'No conversations match "${_searchQuery.trim()}".'
                                : 'No ${_filters[_filterIndex].toLowerCase()} conversations.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                          itemCount: _visible.length,
                          separatorBuilder: (_, __) => Divider(color: theme.foreground.withValues(alpha: 0.1), height: 1),
                          itemBuilder: (context, index) {
                            final thread = _visible[index];
                            return InkWell(
                              onTap: () => _openThread(thread),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: ChatThreadListTile(
                                  thread: thread,
                                  avatar: const LandlordAvatar(radius: 26),
                                  nameMessageSpacing: 3,
                                  nameStyle: AppTextStyles.body(
                                    color: theme.foreground,
                                    size: 15,
                                    weight: FontWeight.w700,
                                  ),
                                  messageStyle: AppTextStyles.body(
                                    color: theme.foreground.withValues(alpha: 0.55),
                                    size: 13,
                                  ),
                                  trailing: thread.unreadCount > 0
                                      ? Container(
                                          width: 18,
                                          height: 18,
                                          alignment: Alignment.center,
                                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                          child: Text(
                                            '${thread.unreadCount}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.navy : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.navy : AppColors.hintGrey.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: AppTextStyles.body(
            color: selected ? AppColors.white : AppColors.hintGrey,
            size: 12.5,
            weight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
