import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/chat.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../services/chat_socket_service.dart';
import '../../state/app_state.dart';
import '../../widgets/chat_thread_list_tile.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_picker_sheet.dart';

/// The admin console's messaging area — the signed-in admin's own inbox
/// (conversations they've been assigned or transferred, same as any other
/// role gets from `ChatRepository.myThreads()`) plus a shared "Support
/// Queue" tab: every open "Contact Support" thread, claimed or not, visible
/// to every admin regardless of participancy (see backend
/// ChatService.findSupportQueue) — that's the fix for "admins never
/// receive support messages," which used to be a fully local, fake UI with
/// no backend thread behind it at all.
class AdminMessagesTab extends StatefulWidget {
  const AdminMessagesTab({super.key});

  @override
  State<AdminMessagesTab> createState() => _AdminMessagesTabState();
}

enum _MessagesView { inbox, supportQueue }

enum _InboxFilter { all, opened, resolved }

class _AdminMessagesTabState extends State<AdminMessagesTab> {
  _MessagesView _view = _MessagesView.inbox;
  _InboxFilter _inboxFilter = _InboxFilter.all;
  List<ChatThread>? _threads;
  List<SupportQueueThread>? _queue;
  String? _error;
  StreamSubscription<ChatSocketMessage>? _socketSubscription;
  StreamSubscription<String>? _claimedSubscription;

  @override
  void initState() {
    super.initState();
    _load();
    // Without this, the inbox only ever refreshed on manual pull-to-
    // refresh or reopening the tab — a message arriving while an admin sat
    // here just never showed up until then.
    _socketSubscription = context.read<AppState>().chatSocket.onNewMessage.listen((_) => _load());
    // A ticket another admin just claimed (opened, or replied to) needs to
    // vanish from *my* Support Queue view live too — a claim carries no
    // message of its own, so onNewMessage alone wouldn't catch it.
    _claimedSubscription = context.read<AppState>().chatSocket.onThreadClaimed.listen((_) => _load());
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _claimedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_view == _MessagesView.inbox) {
        final threads = await context.read<AppState>().chat.myThreads();
        if (!mounted) return;
        setState(() {
          _threads = threads;
          _error = null;
        });
      } else {
        final queue = await context.read<AppState>().chat.supportQueue();
        if (!mounted) return;
        setState(() {
          _queue = queue;
          _error = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load messages.");
    }
  }

  Future<void> _openThread(ChatThread thread) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          theme: DashboardTheme.midnight,
          contactName: thread.otherParticipantName,
          threadId: thread.id,
          adminViewOfUserId: thread.otherParticipants.isNotEmpty ? thread.otherParticipants.first.id : null,
          showExportAction: true,
          otherParticipant: thread.otherParticipant,
          // Only support threads carry resolve/transfer semantics — a
          // regular property/order thread has neither.
          showResolveTransferActions: thread.isSupport,
          isResolved: thread.resolved,
          onResolve: thread.isSupport ? () => _resolve(thread.id) : null,
          onTransfer: thread.isSupport ? () => _transfer(thread.id) : null,
        ),
      ),
    );
    if (!mounted) return;
    _load();
  }

  /// Claims the ticket (moving it into this admin's own inbox) *before*
  /// opening it — that's what makes "opening a message from the queue"
  /// itself the claim, not waiting for a reply. If another admin claimed
  /// it a moment earlier, this throws instead of navigating anywhere.
  Future<void> _openQueueThread(SupportQueueThread thread) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().chat.claimThread(thread.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      _load();
      return;
    }
    if (!mounted) return;
    final requesterName = thread.requesterName?.isNotEmpty == true ? thread.requesterName! : 'A user';
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          theme: DashboardTheme.midnight,
          // The *requester* is the customer, not "HomeServant Support" —
          // that label belongs on the user's own side of this
          // conversation (see support_sheet.dart), never the admin's.
          contactName: requesterName,
          threadId: thread.id,
          adminViewOfUserId: thread.requesterId,
          showExportAction: true,
          showResolveTransferActions: true,
          onResolve: () => _resolve(thread.id),
          onTransfer: () => _transfer(thread.id),
        ),
      ),
    );
    if (!mounted) return;
    _load();
  }

  Future<void> _resolve(String threadId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().chat.resolveThread(threadId);
      messenger.showSnackBar(const SnackBar(content: Text('Marked resolved')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _transfer(String threadId) async {
    final messenger = ScaffoldMessenger.of(context);
    List<AdminAccount> admins;
    try {
      admins = await context.read<AppState>().admin.findAdmins();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    final myId = context.read<AppState>().userId;
    final chosen = await showAdminPickerSheet(
      context,
      admins: admins,
      title: 'Transfer conversation to',
      excludeAdminIds: {if (myId != null) myId},
    );
    if (chosen == null || !mounted) return;
    try {
      await context.read<AppState>().chat.transferThread(threadId, chosen.id);
      messenger.showSnackBar(SnackBar(content: Text('Transferred to ${chosen.email}')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: AdminFilterChip(
                  label: 'Inbox',
                  selected: _view == _MessagesView.inbox,
                  onTap: () => setState(() {
                    _view = _MessagesView.inbox;
                    _threads = null;
                    _load();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AdminFilterChip(
                  label: 'Support Queue',
                  selected: _view == _MessagesView.supportQueue,
                  onTap: () => setState(() {
                    _view = _MessagesView.supportQueue;
                    _queue = null;
                    _load();
                  }),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _view == _MessagesView.inbox ? _buildInbox() : _buildQueue()),
      ],
    );
  }

  Widget _buildInbox() {
    final allThreads = _threads;
    if (allThreads == null) return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    // Unattended (red) is a Support Queue-only concept — a thread that's
    // reached the inbox has, by definition, already been claimed — so the
    // inbox only ever needs to distinguish still-open ("Read") from
    // resolved.
    final threads = switch (_inboxFilter) {
      _InboxFilter.all => allThreads,
      _InboxFilter.opened => allThreads.where((t) => t.isSupport && !t.resolved).toList(),
      _InboxFilter.resolved => allThreads.where((t) => t.isSupport && t.resolved).toList(),
    };
    return Column(
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              AdminFilterChip(
                label: 'All',
                selected: _inboxFilter == _InboxFilter.all,
                onTap: () => setState(() => _inboxFilter = _InboxFilter.all),
              ),
              const SizedBox(width: 8),
              AdminFilterChip(
                label: 'Opened',
                selected: _inboxFilter == _InboxFilter.opened,
                onTap: () => setState(() => _inboxFilter = _InboxFilter.opened),
              ),
              const SizedBox(width: 8),
              AdminFilterChip(
                label: 'Resolved',
                selected: _inboxFilter == _InboxFilter.resolved,
                onTap: () => setState(() => _inboxFilter = _InboxFilter.resolved),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: threads.isEmpty
              ? const Center(child: Text('No conversations yet'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: threads.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      final unread = thread.unreadCount > 0;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _openThread(thread),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: adminCardDecoration,
                                child: ChatThreadListTile(
                                  thread: thread,
                                  avatar: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                                    child: Icon(
                                      thread.isSupport ? Icons.support_agent_rounded : Icons.person,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  nameStyle: AppTextStyles.body(
                                    color: AppColors.navy,
                                    size: 14,
                                    weight: unread ? FontWeight.w800 : FontWeight.w700,
                                  ),
                                  messageStyle: AppTextStyles.body(
                                    color: AppColors.hintGrey,
                                    size: 12.5,
                                    weight: unread ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                  trailing: unread
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration:
                                              BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(9)),
                                          constraints: const BoxConstraints(minWidth: 20),
                                          child: Text(
                                            '${thread.unreadCount}',
                                            textAlign: TextAlign.center,
                                            style: AppTextStyles.body(color: Colors.white, size: 11, weight: FontWeight.w700),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          if (thread.isSupport) ...[
                            const SizedBox(width: 8),
                            _Badge(
                              text: thread.resolved ? 'Resolved' : 'Read',
                              color: thread.resolved ? Colors.green : Colors.blue,
                            ),
                            const SizedBox(width: 4),
                            if (!thread.resolved)
                              IconButton(
                                onPressed: () => _resolve(thread.id),
                                icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green),
                                tooltip: 'Mark resolved',
                              ),
                          ] else
                            IconButton(
                              onPressed: () => _transfer(thread.id),
                              icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.navy),
                              tooltip: 'Transfer to another admin',
                            ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildQueue() {
    final queue = _queue;
    if (queue == null) return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    if (queue.isEmpty) return const Center(child: Text('No open support conversations'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: queue.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final thread = queue[index];
          return InkWell(
            onTap: () => _openQueueThread(thread),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: adminCardDecoration,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.navy.withValues(alpha: 0.1),
                    child: const Icon(Icons.support_agent_rounded, color: AppColors.navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          thread.requesterName?.isNotEmpty == true ? thread.requesterName! : 'A user',
                          style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w700),
                        ),
                        if (thread.lastMessage != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            thread.lastMessage!.type == MessageType.image && thread.lastMessage!.body.isEmpty
                                ? '📷 Photo'
                                : thread.lastMessage!.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatRelativeTime(thread.createdAt), style: AppTextStyles.body(color: AppColors.hintGrey, size: 11)),
                      // The backend now excludes claimed threads from this
                      // queue entirely (see ChatService.findSupportQueue),
                      // so every row here is unattended by construction.
                      const SizedBox(height: 4),
                      const _Badge(text: 'Unattended', color: Colors.red),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: AppTextStyles.body(color: color, size: 10, weight: FontWeight.w700)),
    );
  }
}
