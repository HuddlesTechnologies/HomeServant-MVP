// Admin and support-chat bars shown above the messages: presence under the contact name, the support topic, hand-off history, resolve/transfer/reassign actions, and the user info panel.
part of '../chat_thread_screen.dart';

/// "Active now" (green dot) or "Last active X ago", under the contact
/// name in the AppBar — the same presence snapshot ChatThreadListTile's
/// avatar dot already uses, just spelled out as text here since there's no
/// list of other threads' avatars to dot next to.
Widget _presenceLabel(ThreadParticipant participant, DashboardTheme theme) {
  if (participant.isOnline) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('Active now', style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 11.5)),
      ],
    );
  }
  final lastActiveAt = participant.lastActiveAt;
  if (lastActiveAt == null) return const SizedBox();
  return Text(
    'Last active ${formatRelativeTime(lastActiveAt)}',
    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.5), size: 11.5),
  );
}

/// The literal "at the top of a chat there should be a section that says
/// mark as resolved" bar — a plain green "Resolved" label once [isResolved]
/// (nothing left to do), otherwise a "Mark as Resolved" button plus a
/// "Transfer" icon button. `theme.surface`/`theme.onSurface` are used
/// rather than `theme.background`/`theme.foreground` since this sits as
/// its own raised bar (same convention as [_OrderStatusBanner]/
/// `_RecipientInfoPanel`), and `onSurface` stays navy-on-light-surface
/// across every `DashboardTheme` variant.
class _ResolveTransferBar extends StatelessWidget {
  const _ResolveTransferBar({
    required this.theme,
    required this.isResolved,
    required this.busy,
    required this.onResolve,
    required this.onTransfer,
  });

  final DashboardTheme theme;
  final bool isResolved;
  final bool busy;
  final VoidCallback onResolve;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: isResolved
          ? Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Text('Resolved', style: AppTextStyles.body(color: Colors.green, size: 13.5, weight: FontWeight.w700)),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onResolve,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.green),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 16),
                    label: Text(
                      'Mark as Resolved',
                      style: AppTextStyles.body(color: Colors.green, size: 12.5, weight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: busy ? null : onTransfer,
                  icon: Icon(Icons.swap_horiz_rounded, color: theme.onSurface),
                  tooltip: 'Transfer to another admin',
                ),
              ],
            ),
    );
  }
}

/// A super admin's view into someone else's support conversation: says
/// it's read-only and offers Reassign. theme.surface/onSurface is a fixed
/// light-surface/navy-text pair in every DashboardTheme (see CLAUDE.md);
/// the button uses the accent/onAccent pair.
String _personName(ThreadPersonRef? person, String? myId) {
  if (person == null) return 'a former admin';
  if (person.id == myId) return 'you';
  return person.displayName;
}

String _handoffTime(DateTime at) {
  final local = at.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${formatShortDate(local)}, $hh:$mm';
}

String _describeHandoff(ThreadHandoff entry, String? myId) {
  final to = _personName(entry.to, myId);
  final from = _personName(entry.from, myId);
  final by = _personName(entry.by, myId);
  return switch (entry.kind) {
    HandoffKind.claim => '${_capitalise(to)} took up this conversation',
    HandoffKind.transfer => '${_capitalise(from)} transferred it to $to',
    HandoffKind.reassign => '${_capitalise(by)} (super admin) reassigned it from $from to $to',
    HandoffKind.autoAssign => 'Auto assigned to $to by system admin',
  };
}

String _capitalise(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Admins only: what the customer is contacting support about, as they
/// picked it when opening the chat. theme.surface/onSurface is a fixed
/// light-surface/navy-text pair in every theme.
class _SupportTopicBanner extends StatelessWidget {
  const _SupportTopicBanner({required this.theme, required this.topic});

  final DashboardTheme theme;
  final SupportTopic? topic;

  @override
  Widget build(BuildContext context) {
    final topic = this.topic;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, color: theme.onSurface, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: topic == null
                    ? [const TextSpan(text: "The customer didn't pick a topic for this conversation.")]
                    : [
                        const TextSpan(text: 'Contacting support about: '),
                        TextSpan(text: topic.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: ' · ${topic.hint}'),
                      ],
              ),
              style: AppTextStyles.body(color: theme.onSurface, size: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown above the messages once a support conversation has changed
/// hands: who moved it to whom, and who first took it up.
/// theme.surface/onSurface is a fixed contrast pair in every theme.
class _HandoffBanner extends StatelessWidget {
  const _HandoffBanner({required this.theme, required this.history, required this.myId, required this.onViewHistory});

  final DashboardTheme theme;
  final ThreadHandlingHistory history;
  final String? myId;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final last = history.lastHandoff!;
    final first = history.firstHandler;
    final current = history.currentAdmin;
    final handlingIt = current != null && current.id == myId;
    final headline = handlingIt
        ? switch (last.kind) {
            HandoffKind.reassign => 'Reassigned to you by ${_personName(last.by, myId)}',
            // Nobody handed it over — the system picked this admin.
            HandoffKind.autoAssign => 'Auto Assigned to you by system admin',
            _ => 'Transferred to you by ${_personName(last.from, myId)}',
          }
        : 'Now handled by ${_personName(current, myId)}';
    // "First taken up by" only adds anything once it has changed hands.
    final showFirst = first != null && !(last.kind == HandoffKind.autoAssign && history.entries.length == 1);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.swap_horiz_rounded, color: theme.onSurface, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$headline · ${_handoffTime(last.at)}',
                  style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700),
                ),
                if (showFirst)
                  Text(
                    'First taken up by ${_personName(first, myId)}',
                    style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.7), size: 12),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onViewHistory,
            child: Text('History', style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ReassignBar extends StatelessWidget {
  const _ReassignBar({required this.theme, required this.busy, required this.onReassign});

  final DashboardTheme theme;
  final bool busy;
  final VoidCallback onReassign;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, color: theme.onSurface, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Viewing as super admin',
              style: AppTextStyles.body(color: theme.onSurface, size: 12.5, weight: FontWeight.w600),
            ),
          ),
          ElevatedButton.icon(
            onPressed: busy ? null : onReassign,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accent,
              disabledBackgroundColor: theme.accent.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: Icon(Icons.swap_horiz_rounded, color: theme.onAccent, size: 16),
            label: Text('Reassign', style: AppTextStyles.body(color: theme.onAccent, size: 12.5, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Collapsible box showing everything on file about the person an admin is
/// chatting with — toggled via the AppBar's info icon, so an admin can
/// check who they're replying to without leaving the conversation.
class _RecipientInfoPanel extends StatelessWidget {
  const _RecipientInfoPanel({required this.theme, required this.detail, required this.loading, required this.error});

  final DashboardTheme theme;
  final AdminUserDetail? detail;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : error != null
              ? Text(error!, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 12.5))
              : detail == null
                  ? const SizedBox()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.fullName?.isNotEmpty == true ? detail.fullName! : detail.email,
                          style: AppTextStyles.body(color: theme.onSurface, size: 14.5, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        _InfoRow('Email', detail.email, theme),
                        if (detail.phoneNumber != null && detail.phoneNumber!.isNotEmpty)
                          _InfoRow('Phone', detail.phoneNumber!, theme),
                        _InfoRow('Role', detail.role.adminLabel, theme),
                        if (detail.houseAddress != null && detail.houseAddress!.isNotEmpty)
                          _InfoRow('Address', detail.houseAddress!, theme),
                        if (detail.vendorBusinessName != null) _InfoRow('Shop', detail.vendorBusinessName!, theme),
                        _InfoRow('Joined', formatShortDate(detail.createdAt), theme),
                        if (detail.deactivatedAt != null) _InfoRow('Status', 'Deactivated', theme),
                      ],
                    ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, this.theme);

  final String label;
  final String value;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.5), size: 12)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body(color: theme.onSurface, size: 12.5, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.text, required this.time, required this.isLast, this.emphasised = false});

  final String text;
  final String? time;
  final bool isLast;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: emphasised ? AppColors.gold : AppColors.navy,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: AppColors.navy.withValues(alpha: 0.15))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: AppTextStyles.body(
                      color: AppColors.navy,
                      size: 14,
                      weight: emphasised ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  if (time != null)
                    Text(time!, style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.6), size: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
