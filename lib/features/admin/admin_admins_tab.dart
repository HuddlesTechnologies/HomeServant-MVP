import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'widgets/admin_confirm_sheet.dart';

/// Only reachable by a SUPER_ADMIN — see AdminShell, which hides this
/// destination entirely for MODERATOR/SUPPORT. The server enforces the
/// same restriction independently (AdminLevelGuard), so this screen
/// existing client-side isn't itself a security boundary.
class AdminAdminsTab extends StatefulWidget {
  const AdminAdminsTab({super.key});

  @override
  State<AdminAdminsTab> createState() => _AdminAdminsTabState();
}

class _AdminAdminsTabState extends State<AdminAdminsTab> {
  List<AdminAccount>? _admins;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final admins = await context.read<AppState>().admin.findAdmins();
      if (!mounted) return;
      setState(() {
        _admins = admins;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load admins.");
    }
  }

  Future<void> _changeLevel(AdminAccount admin, AdminLevel level) async {
    if (level == admin.level) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.setAdminLevel(admin.id, level);
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(AdminAccount admin) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: 'Remove admin ${admin.email}?',
      body: "This permanently deletes their account. This can't be undone.",
      actionLabel: 'Remove',
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.removeAdmin(admin.id);
      messenger.showSnackBar(SnackBar(content: Text('${admin.email} removed')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _createAdmin() async {
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    var level = AdminLevel.support;

    final created = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New Admin', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              const SizedBox(height: 16),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Temporary password'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AdminLevel>(
                value: level,
                decoration: const InputDecoration(labelText: 'Level'),
                items: [for (final l in AdminLevel.values) DropdownMenuItem(value: l, child: Text(l.label))],
                onChanged: (value) => setSheetState(() => level = value ?? AdminLevel.support),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Create Admin', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (created != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.createAdmin(
        email: emailController.text.trim(),
        password: passwordController.text,
        fullName: nameController.text.trim(),
        level: level,
      );
      messenger.showSnackBar(const SnackBar(content: Text('Admin created')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admins = _admins;
    final myId = context.watch<AppState>().userId;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAdmin,
        backgroundColor: AppColors.navy,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Admin', style: TextStyle(color: Colors.white)),
      ),
      body: admins == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: admins.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final admin = admins[index];
                  final isSelf = admin.id == myId;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    admin.fullName?.isNotEmpty == true ? admin.fullName! : admin.email,
                                    style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14),
                                  ),
                                  if (isSelf) ...[
                                    const SizedBox(width: 6),
                                    Text('(you)', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(admin.email, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
                            ],
                          ),
                        ),
                        DropdownButton<AdminLevel>(
                          value: admin.level,
                          underline: const SizedBox.shrink(),
                          items: [for (final l in AdminLevel.values) DropdownMenuItem(value: l, child: Text(l.label, style: const TextStyle(fontSize: 13)))],
                          onChanged: (level) => level != null ? _changeLevel(admin, level) : null,
                        ),
                        if (!isSelf)
                          IconButton(
                            onPressed: () => _remove(admin),
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
