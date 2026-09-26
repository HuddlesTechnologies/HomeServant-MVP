import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_permissions.dart';

/// The admin console's own audit trail — every admin login and password
/// change/reset (plus a user-profile edit or a log wipe). Every admin tier
/// can view it; only a SUPER_ADMIN can clear it (server-enforced too, see
/// AdminController.clearActivityLog). Clearing a single type (via the
/// filter chips) is silent; clearing "All" wipes the whole log and writes
/// one ADMIN_ACTIVITY_LOG_CLEARED row right after, naming who did it — see
/// AdminService.clearActivityLog's doc comment.
class AdminActivityLogScreen extends StatefulWidget {
  const AdminActivityLogScreen({super.key});

  @override
  State<AdminActivityLogScreen> createState() => _AdminActivityLogScreenState();
}

class _AdminActivityLogScreenState extends State<AdminActivityLogScreen> {
  List<ActivityLogEntry>? _entries;
  ActivityLogType? _typeFilter;
  bool _hasMore = false;
  int _page = 1;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _entries = null;
      _page = 1;
    });
    try {
      final result = await context.read<AppState>().admin.findActivityLog(page: 1, type: _typeFilter);
      if (!mounted) return;
      setState(() {
        _entries = result.items;
        _hasMore = result.hasMore;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load the activity log.");
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await context.read<AppState>().admin.findActivityLog(page: _page + 1, type: _typeFilter);
      if (!mounted) return;
      setState(() {
        _entries = [...?_entries, ...result.items];
        _page += 1;
        _hasMore = result.hasMore;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _clear() async {
    final type = _typeFilter;
    final confirmed = await showAdminConfirmSheet(
      context,
      title: type == null ? 'Clear the entire activity log?' : "Clear every \"${type.label}\" entry?",
      body: type == null
          ? "This deletes every entry of every type — there's no undo. Because this wipes the whole log, one entry naming you as the super admin who cleared it is written right after."
          : 'This deletes every "${type.label}" entry — there\'s no undo. Clearing a single type like this isn\'t itself logged.',
      actionLabel: 'Clear',
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.clearActivityLog(type: type);
      messenger.showSnackBar(const SnackBar(content: Text('Activity log cleared')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Activity Log', style: AppTextStyles.heading(color: Colors.white, size: 18)),
        actions: [
          if (context.isSuperAdmin)
            IconButton(
              onPressed: _clear,
              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white),
              tooltip: _typeFilter == null ? 'Clear entire log' : 'Clear this type',
            ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                AdminFilterChip(label: 'All', selected: _typeFilter == null, onTap: () => setState(() { _typeFilter = null; _load(); })),
                for (final type in ActivityLogType.values) ...[
                  const SizedBox(width: 8),
                  AdminFilterChip(label: type.label, selected: _typeFilter == type, onTap: () => setState(() { _typeFilter = type; _load(); })),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries == null
                ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
                : entries.isEmpty
                    ? const Center(child: Text('No activity recorded'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: entries.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            if (index == entries.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: _loadingMore ? null : _loadMore,
                                  child: _loadingMore
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text('Load more'),
                                ),
                              );
                            }
                            final entry = entries[index];
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: adminCardDecoration,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.type.label,
                                          style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14),
                                        ),
                                      ),
                                      Text(formatShortDate(entry.createdAt), style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry.target != null && entry.target!.id != entry.actor?.id
                                        ? '${entry.actor?.displayName ?? 'Unknown'} → ${entry.target!.displayName}'
                                        : entry.actor?.displayName ?? 'Unknown',
                                    style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600),
                                  ),
                                  if (entry.ip != null || entry.location != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      [if (entry.ip != null) entry.ip, if (entry.location != null) entry.location].join(' · '),
                                      style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
