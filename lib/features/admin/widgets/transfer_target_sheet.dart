import 'package:flutter/material.dart';
import '../../../api/models/admin_models.dart';
import '../../../api/models/support_tools.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import 'admin_filter_chip.dart';

/// Picks the admin to hand a support conversation to. Each row shows what
/// matters for choosing someone who can actually help: their permission
/// level, whether they're on duty and online, and how many open chats they
/// already have. Filter by level and to on-duty only; the most available
/// people are listed first. White sheet, navy text (the console palette).
Future<TransferTarget?> showTransferTargetSheet(
  BuildContext context, {
  required List<TransferTarget> admins,
  String title = 'Transfer to',
  Set<String> excludeAdminIds = const {},
}) {
  return showModalBottomSheet<TransferTarget>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => _TransferTargetSheet(
      admins: admins.where((a) => !excludeAdminIds.contains(a.id)).toList(),
      title: title,
    ),
  );
}

class _TransferTargetSheet extends StatefulWidget {
  const _TransferTargetSheet({required this.admins, required this.title});

  final List<TransferTarget> admins;
  final String title;

  @override
  State<_TransferTargetSheet> createState() => _TransferTargetSheetState();
}

class _TransferTargetSheetState extends State<_TransferTargetSheet> {
  /// null = every level.
  AdminLevel? _level;
  bool _onDutyOnly = false;

  int _availability(TransferTarget a) => (a.onDuty ? 0 : 2) + (a.isOnline ? 0 : 1);

  @override
  Widget build(BuildContext context) {
    final visible = widget.admins
        .where((a) => (_level == null || a.level == _level) && (!_onDutyOnly || a.onDuty))
        .toList()
      ..sort((a, b) => _availability(a).compareTo(_availability(b)) != 0
          ? _availability(a).compareTo(_availability(b))
          : a.openChats.compareTo(b.openChats));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              const SizedBox(height: 4),
              Text(
                'Pick someone with the right access who is available.',
                style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.65), size: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  AdminFilterChip(label: 'All levels', selected: _level == null, onTap: () => setState(() => _level = null)),
                  for (final level in AdminLevel.values)
                    AdminFilterChip(
                      label: '${level.label} (${widget.admins.where((a) => a.level == level).length})',
                      selected: _level == level,
                      onTap: () => setState(() => _level = level),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _onDutyOnly,
                activeColor: AppColors.navy,
                onChanged: (v) => setState(() => _onDutyOnly = v),
                title: Text('On duty only', style: AppTextStyles.body(color: AppColors.navy, size: 13.5, weight: FontWeight.w600)),
              ),
              const Divider(height: 1),
              if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    widget.admins.isEmpty ? 'No other admins available.' : 'No admins match these filters.',
                    style: AppTextStyles.body(color: AppColors.hintGrey, size: 13.5),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _TargetRow(
                      admin: visible[index],
                      onTap: () => Navigator.of(context).pop(visible[index]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.admin, required this.onTap});

  final TransferTarget admin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = !admin.onDuty ? 'Away' : (admin.isOnline ? 'On duty · Online' : 'On duty · Offline');
    final statusColor = !admin.onDuty
        ? AppColors.hintGrey
        : admin.isOnline
            ? const Color(0xFF1E6B3A)
            : AppColors.landlordBrown;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    admin.displayName,
                    style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$status · ${admin.openChats} open ${admin.openChats == 1 ? 'chat' : 'chats'}',
                    style: AppTextStyles.body(color: statusColor, size: 12.5, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            // Level badge: navy text on a pale navy tint (super admin gold
            // tint with brown text) — dark-on-light either way.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: admin.level.isSuperAdmin ? AppColors.gold.withValues(alpha: 0.35) : AppColors.navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                admin.level.label,
                style: AppTextStyles.body(
                  color: admin.level.isSuperAdmin ? AppColors.landlordBrown : AppColors.navy,
                  size: 11.5,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
