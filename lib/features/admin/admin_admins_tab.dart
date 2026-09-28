import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import '../../widgets/otp_input_row.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_filter_chip.dart';

/// A "New Admin" invite that was started but not finished (app closed, sheet
/// dismissed, code never arrived) — persisted so it can be resumed instead of
/// forcing the admin to start over. Never holds the OTP itself: that's only
/// ever emailed, never returned to the client (see AdminService.confirmAdminOtp).
class _AdminCreateDraft {
  _AdminCreateDraft({
    required this.step,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.level,
    this.savedAt,
  });

  /// 'request' — still filling the first form, nothing sent yet.
  /// 'confirm' — requestAdmin succeeded; a code/temp password is already
  /// sitting in that email's inbox and the server has a pending invite.
  final String step;
  final String email;
  final String firstName;
  final String lastName;
  final AdminLevel level;

  /// When a 'confirm' draft was saved — the emailed code only lives
  /// [_inviteCodeLifetime], so after that there's nothing left to resume.
  final DateTime? savedAt;

  /// True while the emailed confirmation code can still be entered. A draft
  /// saved before this was recorded has no [savedAt] and counts as expired.
  bool get codeStillValid => savedAt != null && DateTime.now().difference(savedAt!) < _inviteCodeLifetime;

  Map<String, dynamic> toJson() => {
    'step': step,
    'email': email,
    'firstName': firstName,
    'lastName': lastName,
    'level': level.apiValue,
    if (savedAt != null) 'savedAt': savedAt!.toIso8601String(),
  };

  static _AdminCreateDraft? tryParse(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      // Drafts saved before first/last name were separate hold one fullName.
      final legacy = (json['fullName'] as String? ?? '').trim();
      final space = legacy.indexOf(' ');
      return _AdminCreateDraft(
        step: json['step'] as String,
        email: json['email'] as String,
        firstName: json['firstName'] as String? ?? (space < 0 ? legacy : legacy.substring(0, space)),
        lastName: json['lastName'] as String? ?? (space < 0 ? '' : legacy.substring(space + 1).trim()),
        level: AdminLevel.fromApi(json['level'] as String),
        savedAt: json['savedAt'] != null ? DateTime.tryParse(json['savedAt'] as String) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

const _adminDraftPrefsKey = 'admin_create_draft_v1';

/// Matches the backend's OTP lifetime (CODE_TTL_MINUTES in
/// backend/src/otp/otp.service.ts).
const _inviteCodeLifetime = Duration(minutes: 10);

Future<_AdminCreateDraft?> _loadAdminDraft() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_adminDraftPrefsKey);
  return raw == null ? null : _AdminCreateDraft.tryParse(raw);
}

Future<void> _saveAdminDraft(_AdminCreateDraft draft) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_adminDraftPrefsKey, jsonEncode(draft.toJson()));
}

Future<void> _clearAdminDraft() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_adminDraftPrefsKey);
}

enum _DraftAction { resume, startOver }

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

  /// Search by name or email, and filter by level (null = every level).
  final _search = TextEditingController();
  AdminLevel? _levelFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AdminAccount> _visible(List<AdminAccount> admins) {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final a in admins)
        if ((_levelFilter == null || a.level == _levelFilter) &&
            (query.isEmpty ||
                (a.fullName ?? '').toLowerCase().contains(query) ||
                a.email.toLowerCase().contains(query)))
          a,
    ];
  }

  /// Search box and level chips (white card, navy text — explicit colours).
  Widget _searchAndFilter(List<AdminAccount> admins) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          style: AppTextStyles.body(color: AppColors.navy, size: 14),
          cursorColor: AppColors.navy,
          decoration: InputDecoration(
            hintText: 'Search admins by name or email',
            hintStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.hintGrey),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.hintGrey),
                    tooltip: 'Clear search',
                    onPressed: () => setState(_search.clear),
                  ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            AdminFilterChip(label: 'All (${admins.length})', selected: _levelFilter == null, onTap: () => setState(() => _levelFilter = null)),
            for (final level in [AdminLevel.superAdmin, AdminLevel.moderator, AdminLevel.support])
              AdminFilterChip(
                label: '${level == AdminLevel.support ? 'Support' : '${level.label}s'} (${admins.where((a) => a.level == level).length})',
                selected: _levelFilter == level,
                onTap: () => setState(() => _levelFilter = level),
              ),
          ],
        ),
      ],
    );
  }

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

  void _showAdminDetails(AdminAccount admin, List<AdminAccount> all) {
    final created = admin.createdAt.toLocal();
    final time = '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    final creatorStillAdmin = admin.createdById != null && all.any((a) => a.id == admin.createdById);
    final createdBy = admin.createdByName != null
        ? '${admin.createdByName}${creatorStillAdmin ? '' : ' (no longer an admin)'}'
        : 'Not recorded. This account was set up before this was tracked, as the first admin, or directly in the database.';
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 13))),
          Expanded(child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 13.5, weight: FontWeight.w600))),
        ],
      ),
    );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                admin.fullName?.isNotEmpty == true ? admin.fullName! : admin.email,
                style: AppTextStyles.heading(color: AppColors.navy, size: 18),
              ),
              const SizedBox(height: 10),
              row('Email', admin.email),
              row('Level', admin.level.label),
              row('Account created', '${formatShortDate(created)}, $time'),
              row('Invited by', createdBy),
              row('Two-factor', admin.twoFactorEnabled ? 'On' : 'Off'),
              row('Password', admin.mustChangePassword ? 'Still using the temporary password' : 'Set by them'),
            ],
          ),
        ),
      ),
    );
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

  Future<_DraftAction?> _showResumeAdminDialog(String email) {
    return showDialog<_DraftAction>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Continue inviting $email?', style: AppTextStyles.heading(color: AppColors.navy, size: 17)),
        content: Text(
          "This invite wasn't finished. A confirmation code and one-time password were sent in the last 10 minutes — you can enter that code now, or start the invite over.",
          style: AppTextStyles.body(color: AppColors.hintGrey, size: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Not Now', style: AppTextStyles.body(color: AppColors.hintGrey, size: 14, weight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DraftAction.startOver),
            child: Text('Start Over', style: AppTextStyles.body(color: Colors.redAccent, size: 14, weight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_DraftAction.resume),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy),
            child: const Text('Continue', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _createAdmin() async {
    var existingDraft = await _loadAdminDraft();
    if (!mounted) return;

    String? prefillEmail;
    String? prefillFirstName;
    String? prefillLastName;
    AdminLevel? prefillLevel;

    // An invite that has since been completed (e.g. from another device)
    // leaves nothing to resume.
    final draftEmail = existingDraft?.email.toLowerCase();
    if (draftEmail != null && (_admins ?? const []).any((a) => a.email.toLowerCase() == draftEmail)) {
      await _clearAdminDraft();
      if (!mounted) return;
      existingDraft = null;
    }

    if (existingDraft != null) {
      // Only offer to resume while the emailed code still works. This used
      // to prompt forever: closing the code sheet any way other than its
      // Cancel button (swipe down, tap outside, back, or "Not Now") kept
      // the draft, long after the 10-minute code had expired. An expired
      // one now just pre-fills the form instead.
      if (existingDraft.step == 'confirm' && existingDraft.codeStillValid) {
        final action = await _showResumeAdminDialog(existingDraft.email);
        if (!mounted) return;
        if (action == _DraftAction.resume) {
          await _confirmAdmin(
            existingDraft.email,
            firstName: existingDraft.firstName,
            lastName: existingDraft.lastName,
            level: existingDraft.level,
          );
          return;
        } else if (action == _DraftAction.startOver) {
          await _clearAdminDraft();
          if (!mounted) return;
        } else {
          // "Not Now" — leave the pending draft alone for next time.
          return;
        }
      } else {
        prefillEmail = existingDraft.email;
        prefillFirstName = existingDraft.firstName;
        prefillLastName = existingDraft.lastName;
        prefillLevel = existingDraft.level;
      }
    }

    final emailController = TextEditingController(text: prefillEmail ?? '');
    final firstNameController = TextEditingController(text: prefillFirstName ?? '');
    final lastNameController = TextEditingController(text: prefillLastName ?? '');
    var level = prefillLevel ?? AdminLevel.support;

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
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: firstNameController,
                      textCapitalization: TextCapitalization.words,
                      style: AppTextStyles.body(color: AppColors.navy, size: 14),
                      decoration: InputDecoration(
                        labelText: 'First name',
                        labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: lastNameController,
                      textCapitalization: TextCapitalization.words,
                      style: AppTextStyles.body(color: AppColors.navy, size: 14),
                      decoration: InputDecoration(
                        labelText: 'Last name',
                        labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Customers only see the first name when this admin replies.',
                style: AppTextStyles.body(color: AppColors.hintGrey, size: 12),
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
                style: AppTextStyles.body(color: AppColors.navy, size: 14),
                dropdownColor: Colors.white,
                decoration: InputDecoration(
                  labelText: 'Level',
                  labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                ),
                items: [
                  for (final l in AdminLevel.values)
                    DropdownMenuItem(value: l, child: Text(l.label, style: AppTextStyles.body(color: AppColors.navy, size: 14))),
                ],
                onChanged: (value) => setSheetState(() => level = value ?? AdminLevel.support),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.navy),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('Send Code', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (requested == false) {
      // Explicit Cancel — discard whatever was typed, don't leave a draft.
      await _clearAdminDraft();
      return;
    }
    if (requested == null) {
      // Dismissed (back/swipe) rather than cancelled — save so it can be
      // resumed later instead of losing what was typed.
      if (!mounted) return;
      final firstName = firstNameController.text.trim();
      final lastName = lastNameController.text.trim();
      final email = emailController.text.trim();
      if (firstName.isNotEmpty || lastName.isNotEmpty || email.isNotEmpty) {
        await _saveAdminDraft(
          _AdminCreateDraft(step: 'request', email: email, firstName: firstName, lastName: lastName, level: level),
        );
      }
      return;
    }
    if (!mounted) return;

    final email = emailController.text.trim();
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (firstName.isEmpty || lastName.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text("Enter the admin's first and last name")));
      await _saveAdminDraft(
        _AdminCreateDraft(step: 'request', email: email, firstName: firstName, lastName: lastName, level: level),
      );
      return;
    }
    try {
      await context.read<AppState>().admin.requestAdmin(
        email: email,
        firstName: firstName,
        lastName: lastName,
        level: level,
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      // Nothing was sent yet, so this is still resumable from the top.
      await _saveAdminDraft(
        _AdminCreateDraft(step: 'request', email: email, firstName: firstName, lastName: lastName, level: level),
      );
      return;
    }
    if (!mounted) return;
    // The server now has a pending invite regardless of what happens to this
    // screen next, so persist enough to resume straight into the confirm step.
    await _saveAdminDraft(
      _AdminCreateDraft(
        step: 'confirm',
        email: email,
        firstName: firstName,
        lastName: lastName,
        level: level,
        savedAt: DateTime.now(),
      ),
    );
    await _confirmAdmin(email, firstName: firstName, lastName: lastName, level: level);
  }

  Future<void> _confirmAdmin(
    String email, {
    required String firstName,
    required String lastName,
    required AdminLevel level,
  }) async {
    var code = '';
    var resending = false;
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
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: resending
                      ? null
                      : () async {
                          setSheetState(() => resending = true);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await context.read<AppState>().admin.requestAdmin(
                              email: email,
                              firstName: firstName,
                              lastName: lastName,
                              level: level,
                            );
                            // A fresh code restarts the resume window.
                            await _saveAdminDraft(
                              _AdminCreateDraft(
                                step: 'confirm',
                                email: email,
                                firstName: firstName,
                                lastName: lastName,
                                level: level,
                                savedAt: DateTime.now(),
                              ),
                            );
                            messenger.showSnackBar(const SnackBar(content: Text('Code resent')));
                          } on ApiException catch (e) {
                            messenger.showSnackBar(SnackBar(content: Text(e.message)));
                          } finally {
                            setSheetState(() => resending = false);
                          }
                        },
                  child: Text(
                    resending ? 'Resending…' : "Didn't get it? Resend code",
                    style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.navy,
                        side: const BorderSide(color: AppColors.navy),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: code.length == 4 ? () => Navigator.of(context).pop(true) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        // Without this, a disabled ElevatedButton falls back
                        // to Material 3's own near-white disabled background
                        // — but the label below is a hardcoded white Text,
                        // which doesn't participate in that state at all, so
                        // it stayed white-on-white the entire time this
                        // button sits disabled (i.e. before the 4-digit code
                        // is fully typed, its normal starting state).
                        disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.35),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Create Admin',
                        style: TextStyle(color: Colors.white.withValues(alpha: code.length == 4 ? 1 : 0.7)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == false) {
      // Explicit Cancel — drop the local draft. Any server-side pending
      // invite is left as-is; it's simply overwritten if this email is ever
      // re-requested (see AdminService.requestAdminOtp).
      await _clearAdminDraft();
      return;
    }
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.confirmAdmin(email: email, code: code);
      await _clearAdminDraft();
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.navy,
                    // See the "Create Admin" button above — same disabled-
                    // background gap.
                    disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.35),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Reset Password',
                    style: TextStyle(color: Colors.white.withValues(alpha: code.length == 4 ? 1 : 0.7)),
                  ),
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
    final visible = admins == null ? const <AdminAccount>[] : _visible(admins);
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
                // Headcount by level, then search and level filter, then
                // the matching admins (or a "no matches" line).
                itemCount: 2 + (visible.isEmpty ? 1 : visible.length),
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, rawIndex) {
                  if (rawIndex == 0) return _AdminCounts(admins: admins);
                  if (rawIndex == 1) return _searchAndFilter(admins);
                  if (visible.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No admins match your search.',
                          style: AppTextStyles.body(color: AppColors.hintGrey, size: 14),
                        ),
                      ),
                    );
                  }
                  final admin = visible[rawIndex - 2];
                  final isSelf = admin.id == myId;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    // Tap for who invited this admin (and when the account was created).
                    onTap: () => _showAdminDetails(admin, admins),
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
                                  Flexible(
                                    child: Text(
                                      admin.fullName?.isNotEmpty == true ? admin.fullName! : admin.email,
                                      style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelf) ...[
                                    const SizedBox(width: 6),
                                    Text('(you)', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(admin.email, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
                              const SizedBox(height: 2),
                              Text(
                                'Created ${formatShortDate(admin.createdAt.toLocal())}',
                                style: AppTextStyles.body(color: AppColors.navy, size: 11.5, weight: FontWeight.w600),
                              ),
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
                                dropdownColor: Colors.white,
                                style: AppTextStyles.body(color: AppColors.navy, size: 13),
                                items: [
                                  for (final l in AdminLevel.values)
                                    DropdownMenuItem(value: l, child: Text(l.label, style: AppTextStyles.body(color: AppColors.navy, size: 13))),
                                ],
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
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Headcount by level, for super admins: total, then each level.
class _AdminCounts extends StatelessWidget {
  const _AdminCounts({required this.admins});

  final List<AdminAccount> admins;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int count) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: adminCardDecoration,
        child: Column(
          children: [
            Text('$count', style: AppTextStyles.heading(color: AppColors.navy, size: 20)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5, weight: FontWeight.w600)),
          ],
        ),
      ),
    );
    int count(AdminLevel level) => admins.where((a) => a.level == level).length;
    // Equal-height tiles even when a label wraps on a narrow screen.
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile('All admins', admins.length),
        const SizedBox(width: 8),
        tile('Super admins', count(AdminLevel.superAdmin)),
        const SizedBox(width: 8),
        tile('Moderators', count(AdminLevel.moderator)),
        const SizedBox(width: 8),
        tile('Support', count(AdminLevel.support)),
      ],
      ),
    );
  }
}
