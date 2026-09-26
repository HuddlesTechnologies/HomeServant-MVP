import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/chat_log.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/admin_filter_chip.dart';

enum _ChatLogFilter { all, unattended, opened, resolved }

/// SUPER_ADMIN-only audit view (see AdminController.findChatLog) — every
/// support thread from the last 30 days across *every* admin, not just the
/// viewing admin's own conversations. Unlike AdminMessagesTab's Inbox/Queue,
/// this is read-only history: who's on it now, the full transfer chain
/// (not just the current handler), and the message log itself.
class AdminChatLogScreen extends StatefulWidget {
  const AdminChatLogScreen({super.key});

  @override
  State<AdminChatLogScreen> createState() => _AdminChatLogScreenState();
}

class _AdminChatLogScreenState extends State<AdminChatLogScreen> {
  List<ChatLogEntry>? _entries;
  _ChatLogFilter _filter = _ChatLogFilter.all;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entries = await context.read<AppState>().admin.findChatLog();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load the chat log.");
    }
  }

  void _openEntry(ChatLogEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          theme: DashboardTheme.midnight,
          contactName: entry.requesterName?.isNotEmpty == true ? entry.requesterName! : 'A user',
          threadId: entry.id,
          showExportAction: true,
          readOnly: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = _entries;
    final entries = allEntries == null
        ? null
        : switch (_filter) {
            _ChatLogFilter.all => allEntries,
            _ChatLogFilter.unattended => allEntries.where((e) => e.status == ChatLogStatus.unattended).toList(),
            _ChatLogFilter.opened => allEntries.where((e) => e.status == ChatLogStatus.opened).toList(),
            _ChatLogFilter.resolved => allEntries.where((e) => e.status == ChatLogStatus.resolved).toList(),
          };
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Chat Log', style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                AdminFilterChip(label: 'All', selected: _filter == _ChatLogFilter.all, onTap: () => setState(() => _filter = _ChatLogFilter.all)),
                const SizedBox(width: 8),
                AdminFilterChip(
                  label: 'Unattended',
                  selected: _filter == _ChatLogFilter.unattended,
                  onTap: () => setState(() => _filter = _ChatLogFilter.unattended),
                ),
                const SizedBox(width: 8),
                AdminFilterChip(
                  label: 'Opened',
                  selected: _filter == _ChatLogFilter.opened,
                  onTap: () => setState(() => _filter = _ChatLogFilter.opened),
                ),
                const SizedBox(width: 8),
                AdminFilterChip(
                  label: 'Resolved',
                  selected: _filter == _ChatLogFilter.resolved,
                  onTap: () => setState(() => _filter = _ChatLogFilter.resolved),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries == null
                ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
                : entries.isEmpty
                    ? const Center(child: Text('No support chats in the last 30 days'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) => _ChatLogRow(entry: entries[index], onTap: () => _openEntry(entries[index])),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ChatLogRow extends StatelessWidget {
  const _ChatLogRow({required this.entry, required this.onTap});

  final ChatLogEntry entry;
  final VoidCallback onTap;

  Color get _badgeColor => switch (entry.status) {
    ChatLogStatus.unattended => Colors.red,
    ChatLogStatus.opened => Colors.blue,
    ChatLogStatus.resolved => Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: adminCardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.requesterName?.isNotEmpty == true ? entry.requesterName! : 'A user',
                    style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(entry.status.label, style: AppTextStyles.body(color: _badgeColor, size: 10, weight: FontWeight.w700)),
                ),
              ],
            ),
            if (entry.lastMessageBody != null) ...[
              const SizedBox(height: 4),
              Text(
                entry.lastMessageBody!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
              ),
            ],
            const SizedBox(height: 6),
            if (entry.currentAdminName != null)
              Text(
                'Attended by: ${entry.currentAdminName}',
                style: AppTextStyles.body(color: AppColors.navy, size: 12, weight: FontWeight.w600),
              ),
            if (entry.wasTransferred) ...[
              const SizedBox(height: 2),
              Text(
                'Transferred ${entry.transferChain.length - 1}× — ${entry.transferChain.join(' → ')}',
                style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
              ),
            ],
            const SizedBox(height: 4),
            Text(formatRelativeTime(entry.createdAt), style: AppTextStyles.body(color: AppColors.hintGrey, size: 11)),
          ],
        ),
      ),
    );
  }
}
