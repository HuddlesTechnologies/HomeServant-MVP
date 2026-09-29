import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_exception.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../models/dashboard_theme.dart';
import '../state/app_state.dart';

/// What the user is reporting.
enum ReportTarget { property, product }

const _propertyReasons = [
  'Looks like a scam or fake listing',
  'Photos or details are misleading',
  'Asked me to pay outside HomeServant',
  'Landlord behaved inappropriately',
  'Something else',
];

const _productReasons = [
  'Item not as described',
  'Never received it',
  'Counterfeit or unsafe',
  'Seller behaved inappropriately',
  'Something else',
];

/// "Report this listing/item" — pick a reason, add details, send it to
/// HomeServant's team (it lands in the admin Reports queue). The sheet
/// uses the theme's fixed surface/onSurface pair; the text field sets its
/// own navy-on-white colours (see CLAUDE.md).
Future<void> showReportSheet(
  BuildContext context, {
  required DashboardTheme theme,
  required ReportTarget target,
  required String targetId,
  required String targetName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ReportSheet(theme: theme, target: target, targetId: targetId, targetName: targetName),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({required this.theme, required this.target, required this.targetId, required this.targetName});

  final DashboardTheme theme;
  final ReportTarget target;
  final String targetId;
  final String targetName;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Pick what the problem is');
      return;
    }
    final details = _details.text.trim();
    final text = details.isEmpty ? reason : '$reason — $details';
    if (text.length < 10) {
      setState(() => _error = 'Add a little more detail');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final reports = context.read<AppState>().reports;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (widget.target == ReportTarget.property) {
        await reports.reportProperty(widget.targetId, text);
      } else {
        await reports.reportProduct(widget.targetId, text);
      }
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text("Thanks — our team will look into it. You'll be told when it's been reviewed.")),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final reasons = widget.target == ReportTarget.property ? _propertyReasons : _productReasons;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.target == ReportTarget.property ? 'Report this listing' : 'Report this item',
                style: AppTextStyles.heading(color: theme.onSurface, size: 18),
              ),
              const SizedBox(height: 4),
              Text(widget.targetName, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.7), size: 13)),
              const SizedBox(height: 12),
              for (final reason in reasons)
                RadioListTile<String>(
                  value: reason,
                  groupValue: _reason,
                  onChanged: (value) => setState(() => _reason = value),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeColor: theme.onSurface,
                  title: Text(reason, style: AppTextStyles.body(color: theme.onSurface, size: 14)),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                minLines: 2,
                maxLines: 5,
                maxLength: 1000,
                style: AppTextStyles.body(color: AppColors.navy, size: 14),
                cursorColor: AppColors.navy,
                decoration: InputDecoration(
                  hintText: 'What happened? (optional)',
                  hintStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 14),
                  counterStyle: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 11),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: AppTextStyles.body(color: const Color(0xFFB42318), size: 12.5, weight: FontWeight.w600)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _sending ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.accent,
                    disabledBackgroundColor: theme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                  ),
                  child: _sending
                      ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: theme.onAccent))
                      : Text('Send report', style: AppTextStyles.button(color: theme.onAccent, size: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
