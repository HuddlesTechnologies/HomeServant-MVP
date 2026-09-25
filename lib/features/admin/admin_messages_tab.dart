import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/chat.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/chat_thread_list_tile.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_picker_sheet.dart';

/// The admin console's own inbox — every chat thread the signed-in admin
/// is a participant in (tenant/landlord/vendor conversations they've been
/// assigned, plus anything transferred to them). `ChatRepository.myThreads()`
/// already returns exactly this for whichever role holds the bearer token,
/// so this is a straight reuse of the same repository/tile the tenant and
/// landlord Messages screens use, plus a transfer action neither of those
/// roles need.
class AdminMessagesTab extends StatefulWidget {
  const AdminMessagesTab({super.key});

  @override
  State<AdminMessagesTab> createState() => _AdminMessagesTabState();
}

class _AdminMessagesTabState extends State<AdminMessagesTab> {
  List<ChatThread>? _threads;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final threads = await context.read<AppState>().chat.myThreads();
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _error = null;
      });
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
        ),
      ),
    );
    if (!mounted) return;
    _load();
  }

  Future<void> _transfer(ChatThread thread) async {
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
      await context.read<AppState>().chat.transferThread(thread.id, chosen.id);
      messenger.showSnackBar(SnackBar(content: Text('Transferred to ${chosen.email}')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final threads = _threads;
    return threads == null
        ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
        : threads.isEmpty
            ? const Center(child: Text('No conversations yet'))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                                  child: const Icon(Icons.person, color: AppColors.navy),
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
                                        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(9)),
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
                        IconButton(
                          onPressed: () => _transfer(thread),
                          icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.navy),
                          tooltip: 'Transfer to another admin',
                        ),
                      ],
                    );
                  },
                ),
              );
  }
}
