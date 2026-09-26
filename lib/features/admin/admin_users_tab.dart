import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/auth_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../dashboard/chat_thread_screen.dart';
import 'admin_user_detail_screen.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_permissions.dart';
import 'widgets/admin_search_bar.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key, this.initialRoleFilter, this.initialShowDeactivatedOnly = false});

  /// Pre-selects a role chip — set when navigating in from a dashboard tile
  /// (e.g. "Tenants") instead of landing on the default "All" view.
  final UserRole? initialRoleFilter;

  /// Pre-selects the "Deactivated" chip — set from the dashboard's
  /// "Deactivated Accounts" tile.
  final bool initialShowDeactivatedOnly;

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  List<AdminUser>? _users;
  String _search = '';
  late UserRole? _roleFilter = widget.initialRoleFilter;
  late bool _deactivatedOnly = widget.initialShowDeactivatedOnly;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await context.read<AppState>().admin.findUsers(
        role: _roleFilter?.apiValue,
        search: _search,
        deactivatedOnly: _deactivatedOnly,
      );
      if (!mounted) return;
      setState(() {
        _users = page.items;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load users.");
    }
  }

  Future<void> _deactivate(AdminUser user) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: 'Deactivate ${user.email}?',
      body: 'Their listings (if any) will be hidden and every session signed out. They can reactivate by logging back in.',
      actionLabel: 'Deactivate',
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.deactivateUser(user.id);
      messenger.showSnackBar(SnackBar(content: Text('${user.email} deactivated')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openDetail(AdminUser user) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminUserDetailScreen(userId: user.id)),
    );
  }

  Future<void> _message(AdminUser user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final thread = await context.read<AppState>().chat.openThread(recipientId: user.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            theme: DashboardTheme.midnight,
            contactName: user.fullName?.isNotEmpty == true ? user.fullName! : user.email,
            threadId: thread.id,
            adminViewOfUserId: user.id,
            showExportAction: true,
            otherParticipant: thread.otherParticipant,
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(AdminUser user) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: 'Permanently delete ${user.email}?',
      body: "This can't be undone — their account and everything tied to it (listings, bookings, orders, messages) will be deleted.",
      actionLabel: 'Delete',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.deleteUser(user.id);
      messenger.showSnackBar(SnackBar(content: Text('${user.email} deleted')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users;
    return Column(
      children: [
        AdminSearchBar(
          hint: 'Search by name or email',
          onChanged: (value) {
            _search = value;
            _load();
          },
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              AdminFilterChip(label: 'All', selected: _roleFilter == null && !_deactivatedOnly, onTap: () => setState(() { _roleFilter = null; _deactivatedOnly = false; _load(); })),
              const SizedBox(width: 8),
              AdminFilterChip(label: 'Tenants', selected: _roleFilter == UserRole.tenant, onTap: () => setState(() { _roleFilter = UserRole.tenant; _deactivatedOnly = false; _load(); })),
              const SizedBox(width: 8),
              AdminFilterChip(label: 'Landlords', selected: _roleFilter == UserRole.landlord, onTap: () => setState(() { _roleFilter = UserRole.landlord; _deactivatedOnly = false; _load(); })),
              const SizedBox(width: 8),
              AdminFilterChip(label: 'Vendors', selected: _roleFilter == UserRole.vendor, onTap: () => setState(() { _roleFilter = UserRole.vendor; _deactivatedOnly = false; _load(); })),
              const SizedBox(width: 8),
              AdminFilterChip(label: 'Deactivated', selected: _deactivatedOnly, onTap: () => setState(() { _roleFilter = null; _deactivatedOnly = true; _load(); })),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: users == null
              ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
              : users.isEmpty
              ? const Center(child: Text('No users found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return InkWell(
                        onTap: () => _openDetail(user),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: adminCardDecoration,
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          user.fullName?.isNotEmpty == true ? user.fullName! : user.email,
                                          style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        _Badge(text: user.role.adminLabel, color: AppColors.navy),
                                        if (user.isDeactivated) ...[
                                          const SizedBox(width: 6),
                                          const _Badge(text: 'Deactivated', color: Colors.redAccent),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(user.email, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _message(user),
                                icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.navy),
                                tooltip: 'Message',
                              ),
                              if (context.canModerate || !user.isDeactivated)
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'deactivate') _deactivate(user);
                                    if (value == 'delete') _delete(user);
                                  },
                                  itemBuilder: (context) => [
                                    if (!user.isDeactivated)
                                      const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
                                    // Deleting is more consequential than
                                    // deactivating — matches the backend's
                                    // MinAdminLevel(MODERATOR) on DELETE
                                    // /admin/users/:id.
                                    if (context.canModerate)
                                      const PopupMenuItem(value: 'delete', child: Text('Delete permanently')),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: AppTextStyles.body(color: color, size: 10.5, weight: FontWeight.w700)),
    );
  }
}
