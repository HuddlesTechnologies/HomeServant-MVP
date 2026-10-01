import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/api_exception.dart';
import '../../api/models/eviction.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/admin_filter_chip.dart';

const _red = Color(0xFFC53030);
const _green = Color(0xFF2F855A);
const _amber = Color(0xFFB7791F);

/// Super admins: landlord eviction requests awaiting a decision. Each case
/// shows the landlord's reason, the tenant's response and the lease, and
/// approving ends the tenancy today (backend EvictionsService.review).
class AdminEvictionsTab extends StatefulWidget {
  const AdminEvictionsTab({super.key});

  @override
  State<AdminEvictionsTab> createState() => _AdminEvictionsTabState();
}

class _AdminEvictionsTabState extends State<AdminEvictionsTab> {
  static const _filters = <(String, String?)>[
    ('Under review', 'PENDING'),
    ('Approved', 'APPROVED'),
    ('Rejected', 'REJECTED'),
    ('Withdrawn', 'CANCELLED'),
    ('All', null),
  ];
  String? _status = 'PENDING';
  List<EvictionRequest>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await context.read<AppState>().evictionsRepo.adminList(status: _status);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _decide(EvictionRequest request, {required bool approve}) async {
    final decided = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DecisionSheet(request: request, approve: approve),
    );
    if (decided == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (label, value) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AdminFilterChip(
                      label: label,
                      selected: _status == value,
                      onTap: () {
                        setState(() {
                          _status = value;
                          _items = null;
                        });
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body(color: _red)),
            )
          else if (items == null)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator(color: AppColors.navy)),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                _status == 'PENDING' ? 'No eviction requests waiting for review.' : 'Nothing here.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: AppColors.hintGrey),
              ),
            )
          else
            for (final request in items)
              _EvictionCard(
                request: request,
                onApprove: () => _decide(request, approve: true),
                onReject: () => _decide(request, approve: false),
              ),
        ],
      ),
    );
  }
}

class _EvictionCard extends StatelessWidget {
  const _EvictionCard({required this.request, required this.onApprove, required this.onReject});

  final EvictionRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  Color get _statusColor => switch (request.status) {
    EvictionStatus.pending => _amber,
    EvictionStatus.approved => _green,
    EvictionStatus.rejected => _red,
    EvictionStatus.cancelled => AppColors.hintGrey,
  };

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.propertyTitle, style: AppTextStyles.body(color: AppColors.navy, size: 15, weight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(r.status.label, style: AppTextStyles.body(color: AppColors.navy, size: 11.5, weight: FontWeight.w700)),
              ),
            ],
          ),
          if (r.propertyLocation.isNotEmpty)
            Text(r.propertyLocation, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
          const SizedBox(height: 10),
          _row('Landlord', _party(r.landlord)),
          _row('Tenant', _party(r.tenant)),
          if (r.leaseStartDate != null && r.leaseEndDate != null)
            _row('Lease', '${formatShortDate(r.leaseStartDate!)} – ${formatShortDate(r.leaseEndDate!)}'),
          _row('Filed', formatShortDate(r.createdAt)),
          const SizedBox(height: 10),
          // Reach either side about the case straight from here.
          _ContactButtons(party: r.tenant, role: 'tenant'),
          const SizedBox(height: 6),
          _ContactButtons(party: r.landlord, role: 'landlord'),
          const SizedBox(height: 10),
          _block("Landlord's reason", r.reason),
          const SizedBox(height: 8),
          _block("Tenant's response", r.tenantResponse ?? 'The tenant has not responded yet.', muted: r.tenantResponse == null),
          if (!r.isPending && r.reviewedAt != null) ...[
            const SizedBox(height: 8),
            _block(
              'Decision',
              '${r.status.label} by ${r.reviewedBy?.name ?? 'a super admin'} on ${formatShortDate(r.reviewedAt!)}'
                  '${r.reviewNote != null ? '\n${r.reviewNote}' : ''}',
            ),
          ],
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.navy),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: onReject,
                    child: Text('Reject', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    onPressed: onApprove,
                    child: Text('Approve eviction', style: AppTextStyles.body(color: AppColors.white, weight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _party(EvictionParty p) => [p.name, if (p.email != null) p.email!, if (p.phone != null) p.phone!].join(' · ');

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 72, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))),
        Expanded(child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 12.5))),
      ],
    ),
  );

  Widget _block(String label, String text, {bool muted = false}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(10)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5, weight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(text, style: AppTextStyles.body(color: muted ? AppColors.hintGrey : AppColors.navy, size: 13)),
      ],
    ),
  );
}

class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({required this.request, required this.approve});

  final EvictionRequest request;
  final bool approve;

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final note = _note.text.trim();
    if (!widget.approve && note.length < 10) {
      setState(() => _error = 'Explain why (at least 10 characters). Both parties see this.');
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().evictionsRepo.review(widget.request.id, approve: widget.approve, note: note);
      navigator.pop(true);
      messenger.showSnackBar(SnackBar(content: Text(widget.approve ? 'Eviction approved; the lease has ended' : 'Eviction request rejected')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approve = widget.approve;
    final r = widget.request;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve ? 'Approve this eviction?' : 'Reject this eviction request?',
              style: AppTextStyles.heading(color: AppColors.navy, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              approve
                  ? "${r.tenant.name}'s lease at ${r.propertyTitle} ends today and the property is listed again. "
                        'Both parties are notified and emailed. This cannot be undone.'
                  : 'The tenancy continues unchanged. Both parties are notified with your note.',
              style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 6,
              maxLength: 2000,
              style: AppTextStyles.body(color: AppColors.navy),
              decoration: InputDecoration(
                hintText: approve ? 'Note to both parties (optional)' : 'Reason for rejecting (required)',
                hintStyle: AppTextStyles.body(color: AppColors.hintGrey),
                counterStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 11),
                errorText: _error,
                errorStyle: AppTextStyles.body(color: _red, size: 12),
                filled: true,
                fillColor: AppColors.offWhite,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: approve ? _red : AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.white))
                    : Text(
                        approve ? 'Approve and end tenancy' : 'Reject request',
                        style: AppTextStyles.body(color: AppColors.white, weight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Message `role`" and "Call `role`" for one side of an eviction case.
/// Navy on the card's white, like the Reject button; Call is disabled (and
/// says so) when that person has no phone number on file.
class _ContactButtons extends StatelessWidget {
  const _ContactButtons({required this.party, required this.role});

  final EvictionParty party;
  final String role;

  Future<void> _message(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final thread = await context.read<AppState>().chat.openThread(recipientId: party.id);
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            theme: DashboardTheme.midnight,
            contactName: party.name,
            threadId: thread.id,
            adminViewOfUserId: party.id,
            showExportAction: true,
            otherParticipant: thread.otherParticipant,
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _call(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));
    var launched = false;
    try {
      launched = await launchUrl(uri);
    } catch (_) {}
    // Nothing on this device places calls (e.g. a desktop browser): show
    // the number so it can be dialled from a phone.
    if (!launched) messenger.showSnackBar(SnackBar(content: Text('Call ${party.name} on $phone')));
  }

  @override
  Widget build(BuildContext context) {
    final phone = party.phone?.trim();
    final hasPhone = phone != null && phone.isNotEmpty;
    Widget button(IconData icon, String label, VoidCallback? onPressed) => OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: onPressed == null ? AppColors.hintGrey : AppColors.navy),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: onPressed == null ? AppColors.hintGrey : AppColors.navy),
      label: Text(
        label,
        style: AppTextStyles.body(color: onPressed == null ? AppColors.hintGrey : AppColors.navy, size: 12.5, weight: FontWeight.w700),
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        button(Icons.chat_bubble_outline_rounded, 'Message $role', () => _message(context)),
        button(Icons.call_outlined, hasPhone ? 'Call $role' : 'No phone for $role', hasPhone ? () => _call(context, phone) : null),
      ],
    );
  }
}
