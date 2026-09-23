import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/landlord_widgets.dart';

enum _ConvoStatus { active, archived, deleted }

class _LandlordConversation {
  _LandlordConversation({
    required this.name,
    required this.preview,
    required this.time,
    required this.unreadCount,
  });

  final String name;
  String preview;
  final String time;
  int unreadCount;
  _ConvoStatus status = _ConvoStatus.active;
}

final _mockConversations = [
  _LandlordConversation(
    name: 'Stephen Sanu',
    preview: 'I would be available this Thursday',
    time: '8:30',
    unreadCount: 1,
  ),
  _LandlordConversation(
    name: 'Ose Ehrabo',
    preview: 'Sie, can i come and inspect or do i have to book?',
    time: '8:30',
    unreadCount: 3,
  ),
  _LandlordConversation(name: 'Michael Kennedy', preview: 'Good afternoon Sir?', time: '8:30', unreadCount: 1),
  _LandlordConversation(
    name: 'Emeka Sunday',
    preview: "That's the price i can give are you still interested?",
    time: '8:30',
    unreadCount: 0,
  ),
  _LandlordConversation(
    name: 'Osi',
    preview: 'I have made payment for the 2 Bedroom apartment',
    time: '8:30',
    unreadCount: 2,
  ),
  _LandlordConversation(
    name: 'Olakunle Biju',
    preview: "That's the price i can give are you still interested?",
    time: '8:30',
    unreadCount: 1,
  ),
  _LandlordConversation(
    name: 'Deshsengan Karul',
    preview: 'I would be available this Thursday',
    time: '8:30',
    unreadCount: 1,
  ),
];

/// Messages tab of the redesigned landlord dashboard: Unread / Deleted /
/// Archived filter pills over a list of tenant conversations, each carrying
/// an unread-count badge instead of the tenant app's plain dot. The search
/// icon filters by name/preview across every conversation, the overflow
/// menu can mark everything read, and each row's own menu can move it
/// between active/archived/deleted — so the Deleted and Archived tabs are
/// real destinations rather than permanently-empty placeholders.
class LandlordMessagesScreen extends StatefulWidget {
  const LandlordMessagesScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<LandlordMessagesScreen> createState() => _LandlordMessagesScreenState();
}

class _LandlordMessagesScreenState extends State<LandlordMessagesScreen> {
  late final List<_LandlordConversation> _conversations = List.of(_mockConversations);
  int _filterIndex = 0;
  bool _searching = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _filters = ['Unread', 'Deleted', 'Archived'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_LandlordConversation> get _visible {
    if (_searching && _searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.trim().toLowerCase();
      return _conversations
          .where(
            (c) =>
                c.status != _ConvoStatus.deleted &&
                (c.name.toLowerCase().contains(query) || c.preview.toLowerCase().contains(query)),
          )
          .toList();
    }
    switch (_filterIndex) {
      case 0:
        return _conversations.where((c) => c.status == _ConvoStatus.active && c.unreadCount > 0).toList();
      case 1:
        return _conversations.where((c) => c.status == _ConvoStatus.deleted).toList();
      default:
        return _conversations.where((c) => c.status == _ConvoStatus.archived).toList();
    }
  }

  Future<void> _openThread(_LandlordConversation convo) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          theme: widget.theme,
          contactName: convo.name,
          initialMessages: [ChatMessage(text: convo.preview, fromMe: false)],
        ),
      ),
    );
    if (!mounted) return;
    setState(() => convo.unreadCount = 0);
  }

  void _markAllRead() {
    setState(() {
      for (final convo in _conversations) {
        convo.unreadCount = 0;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All conversations marked as read')));
  }

  void _setStatus(_LandlordConversation convo, _ConvoStatus status) {
    setState(() => convo.status = status);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final unreadCount = _conversations.where((c) => c.status == _ConvoStatus.active && c.unreadCount > 0).length;

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
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'mark_all_read', child: Text('Mark all as read')),
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
              child: _visible.isEmpty
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
                        final convo = _visible[index];
                        return InkWell(
                          onTap: () => _openThread(convo),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                const LandlordAvatar(radius: 26),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        convo.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.body(
                                          color: theme.foreground,
                                          size: 15,
                                          weight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        convo.preview,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTextStyles.body(
                                          color: theme.foreground.withValues(alpha: 0.55),
                                          size: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      convo.time,
                                      style: AppTextStyles.body(
                                        color: theme.foreground.withValues(alpha: 0.5),
                                        size: 11,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (convo.unreadCount > 0)
                                      Container(
                                        width: 18,
                                        height: 18,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                        child: Text(
                                          '${convo.unreadCount}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                PopupMenuButton<_ConvoStatus>(
                                  icon: Icon(Icons.more_vert_rounded, color: theme.foreground.withValues(alpha: 0.5), size: 18),
                                  onSelected: (status) => _setStatus(convo, status),
                                  itemBuilder: (context) => [
                                    if (convo.status != _ConvoStatus.active)
                                      const PopupMenuItem(value: _ConvoStatus.active, child: Text('Restore')),
                                    if (convo.status != _ConvoStatus.archived)
                                      const PopupMenuItem(value: _ConvoStatus.archived, child: Text('Archive')),
                                    if (convo.status != _ConvoStatus.deleted)
                                      const PopupMenuItem(value: _ConvoStatus.deleted, child: Text('Delete')),
                                  ],
                                ),
                              ],
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
