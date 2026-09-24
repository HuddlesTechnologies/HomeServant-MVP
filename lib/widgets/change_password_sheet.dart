import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_exception.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../state/app_state.dart';

/// Shared by the regular Settings screen and the admin console — anywhere
/// an already-authenticated account needs to change its own password.
Future<void> showChangePasswordSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => const ChangePasswordSheet(),
  );
}

class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key});

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState appState) async {
    final current = _currentController.text;
    final next = _newController.text;
    final confirm = _confirmController.text;
    if (next.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters');
      return;
    }
    if (next != confirm) {
      setState(() => _error = "New passwords don't match");
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await appState.changePassword(currentPassword: current, newPassword: next);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Password updated')));
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Change Password', style: AppTextStyles.heading(color: AppColors.navy, size: 20)),
            const SizedBox(height: 16),
            _PasswordField(controller: _currentController, label: 'Current Password'),
            const SizedBox(height: 12),
            _PasswordField(controller: _newController, label: 'New Password'),
            const SizedBox(height: 12),
            _PasswordField(controller: _confirmController, label: 'Confirm New Password'),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : () => _submit(appState),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                child: Text(_submitting ? 'Updating…' : 'Update Password', style: AppTextStyles.button(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      style: AppTextStyles.body(color: AppColors.navy, size: 14),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscured = !_obscured),
          icon: Icon(
            _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: AppColors.hintGrey,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.navy.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.navy),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
