import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import '../../widgets/otp_input_row.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_filter_chip.dart';

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
    var level = AdminLevel.support;

    final requested = await showModalBottomSheet<bool>(
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
              const SizedBox(height: 6),
              Text(
                "We'll email them a confirmation code and a one-time temporary password.",
                style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                style: AppTextStyles.body(color: AppColors.navy, size: 14),
                decoration: InputDecoration(
                  labelText: 'Full name',
                  labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: AppTextStyles.body(color: AppColors.navy, size: 14),
                decoration: InputDecoration(
                  labelText: 'Email',
                  labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                ),
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
                  child: const Text('Send Code', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (requested != true || !mounted) return;
    final email = emailController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.requestAdmin(email: email, fullName: nameController.text.trim(), level: level);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    await _confirmAdmin(email);
  }

  Future<void> _confirmAdmin(String email) async {
    var code = '';
    final confirmed = await showModalBottomSheet<bool>(
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
              Text('Enter Confirmation Code', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              const SizedBox(height: 6),
              Text(
                'A code and one-time password were sent to $email.',
                style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
              ),
              const SizedBox(height: 20),
              OtpInputRow(
                boxColor: const Color(0xFFF0F1F4),
                textColor: AppColors.navy,
                onChanged: (value) => setSheetState(() => code = value),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: code.length == 4 ? () => Navigator.of(context).pop(true) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Create Admin', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.confirmAdmin(email: email, code: code);
      messenger.showSnackBar(const SnackBar(content: Text('Admin created')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleTwoFactor(AdminAccount admin, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.setAdminTwoFactor(admin.id, enabled);
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Step-up: a code goes to *this* (acting) admin's own email first —
  /// only after entering that does the target's password actually get
  /// reset. See AdminService.requestAdminPasswordReset's doc comment.
  Future<void> _resetPassword(AdminAccount admin) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: "Reset ${admin.email}'s password?",
      body: "A confirmation code will be sent to your own admin email first. Once confirmed, ${admin.email} gets emailed a new one-time temporary password.",
      actionLabel: 'Send Code',
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.requestAdminPasswordReset(admin.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;

    var code = '';
    final myEmail = context.read<AppState>().email;
    final ready = await showModalBottomSheet<bool>(
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
              Text('Confirm It\'s You', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              const SizedBox(height: 6),
              Text('A code was sent to $myEmail.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
              const SizedBox(height: 20),
              OtpInputRow(
                boxColor: const Color(0xFFF0F1F4),
                textColor: AppColors.navy,
                onChanged: (value) => setSheetState(() => code = value),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: code.length == 4 ? () => Navigator.of(context).pop(true) : null,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Reset Password', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ready != true || !mounted) return;
    final messenger2 = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.confirmAdminPasswordReset(admin.id, code);
      messenger2.showSnackBar(SnackBar(content: Text("${admin.email}'s password was reset")));
      _load();
    } on ApiException catch (e) {
      messenger2.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admins = _admins;
    final myId = context.select<AppState, String?>((s) => s.userId);
    final myLevel = context.select<AppState, AdminLevel?>((s) => s.adminLevel);
    final isSuperAdmin = myLevel?.isSuperAdmin ?? false;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: isSuperAdmin
          ? FloatingActionButton.extended(
              onPressed: _createAdmin,
              backgroundColor: AppColors.navy,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('New Admin', style: TextStyle(color: Colors.white)),
            )
          : null,
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
                              if (admin.mustChangePassword) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Hasn\'t set their own password yet',
                                  style: AppTextStyles.body(color: Colors.orange.shade800, size: 11.5, weight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isSuperAdmin) ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              DropdownButton<AdminLevel>(
                                value: admin.level,
                                underline: const SizedBox.shrink(),
                                items: [for (final l in AdminLevel.values) DropdownMenuItem(value: l, child: Text(l.label, style: const TextStyle(fontSize: 13)))],
                                onChanged: (level) => level != null ? _changeLevel(admin, level) : null,
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('2FA', style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5, weight: FontWeight.w600)),
                                  Switch(
                                    value: admin.twoFactorEnabled,
                                    onChanged: (value) => _toggleTwoFactor(admin, value),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ] else ...[
                          Text(admin.level.label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5, weight: FontWeight.w600)),
                        ],
                        // Resetting an admin ranked above you is refused
                        // server-side too (AdminService.requestAdminPasswordReset)
                        // — hidden here just so a MODERATOR isn't shown a
                        // button that would 403 against a SUPER_ADMIN row.
                        if (!isSelf && myLevel != null && myLevel.index >= admin.level.index)
                          IconButton(
                            onPressed: () => _resetPassword(admin),
                            icon: const Icon(Icons.lock_reset_rounded, color: AppColors.navy),
                            tooltip: 'Reset password',
                          ),
                        if (isSuperAdmin && !isSelf)
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
