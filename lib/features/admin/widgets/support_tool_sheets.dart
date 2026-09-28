import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../api/api_exception.dart';
import '../../../api/models/support_tools.dart';
import '../../../core/date_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../state/app_state.dart';
import '../../dashboard/models/property.dart' show formatNaira;
import 'support_triage_badges.dart';

// The admin console's support tools, as bottom sheets opened from a
// support conversation. All are white with navy text (AppColors), and every
// text field sets its text/hint colours explicitly (see CLAUDE.md).

const _sheetShape = RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24)));

TextStyle _body({double size = 14, FontWeight weight = FontWeight.w400, double alpha = 1}) =>
    AppTextStyles.body(color: AppColors.navy.withValues(alpha: alpha), size: size, weight: weight);

InputDecoration _fieldDecoration(String hint) => InputDecoration(
  hintText: hint,
  hintStyle: _body(alpha: 0.45),
  filled: true,
  fillColor: AppColors.navy.withValues(alpha: 0.05),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
);

String _stamp(DateTime at) {
  final t = at.toLocal();
  return '${formatShortDate(t)}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _statusLabel(String raw) =>
    raw.toLowerCase().split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

// --- Internal notes -----------------------------------------------------------

/// Admin-only notes on this conversation — the customer never sees them.
Future<void> showSupportNotesSheet(BuildContext context, String threadId) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: _sheetShape,
    builder: (_) => _NotesSheet(threadId: threadId),
  );
}

class _NotesSheet extends StatefulWidget {
  const _NotesSheet({required this.threadId});
  final String threadId;

  @override
  State<_NotesSheet> createState() => _NotesSheetState();
}

class _NotesSheetState extends State<_NotesSheet> {
  List<SupportNote>? _notes;
  String? _error;
  bool _saving = false;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await context.read<AppState>().supportTools.notes(widget.threadId);
      if (mounted) setState(() => _notes = notes);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _add() async {
    final body = _input.text.trim();
    if (body.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final note = await context.read<AppState>().supportTools.addNote(widget.threadId, body);
      if (!mounted) return;
      setState(() {
        _notes = [...?_notes, note];
        _input.clear();
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Internal notes', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
                const SizedBox(height: 4),
                Text('Only admins see these — never the customer.', style: _body(size: 13, alpha: 0.65)),
                const SizedBox(height: 14),
                Flexible(
                  child: _error != null
                      ? Text(_error!, style: _body(alpha: 0.7))
                      : notes == null
                          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
                          : notes.isEmpty
                              ? Text('No notes yet.', style: _body(alpha: 0.6))
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: notes.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final note = notes[index];
                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.gold.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(note.body, style: _body()),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${note.authorName ?? 'A former admin'} · ${_stamp(note.createdAt)}',
                                            style: _body(size: 11.5, alpha: 0.6),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        style: _body(),
                        cursorColor: AppColors.navy,
                        decoration: _fieldDecoration('Add a note for other admins'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _saving ? null : _add,
                      icon: const Icon(Icons.send_rounded, color: AppColors.navy),
                      tooltip: 'Add note',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Triage -----------------------------------------------------------------

/// Sets the conversation's topic and priority. Returns true if changed.
Future<bool> showTriageSheet(
  BuildContext context,
  String threadId, {
  SupportTopic? topic,
  SupportPriority priority = SupportPriority.normal,
}) async {
  final result = await showModalBottomSheet<(SupportTopic?, SupportPriority)>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: _sheetShape,
    builder: (_) => _TriageSheet(topic: topic, priority: priority),
  );
  if (result == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await context.read<AppState>().supportTools.triage(threadId, topic: result.$1, priority: result.$2);
    messenger.showSnackBar(const SnackBar(content: Text('Conversation updated')));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

class _TriageSheet extends StatefulWidget {
  const _TriageSheet({required this.topic, required this.priority});
  final SupportTopic? topic;
  final SupportPriority priority;

  @override
  State<_TriageSheet> createState() => _TriageSheetState();
}

class _TriageSheetState extends State<_TriageSheet> {
  late SupportTopic? _topic = widget.topic;
  late SupportPriority _priority = widget.priority;

  Widget _pill(String label, bool selected, VoidCallback onTap, {Color color = AppColors.navy}) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: Colors.white,
      selectedColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: AppTextStyles.body(color: selected ? Colors.white : color, size: 13, weight: FontWeight.w600),
      showCheckmark: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Topic & priority', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
            const SizedBox(height: 14),
            Text('Topic', style: _body(weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final topic in SupportTopic.values)
                  _pill(topic.label, _topic == topic, () => setState(() => _topic = topic)),
              ],
            ),
            const SizedBox(height: 16),
            Text('Priority', style: _body(weight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final priority in SupportPriority.values)
                  _pill(
                    priority.label,
                    _priority == priority,
                    () => setState(() => _priority = priority),
                    color: SupportTriageBadges.priorityColor(priority),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () => Navigator.of(context).pop((_topic, _priority)),
                child: Text('Save', style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Saved replies ------------------------------------------------------------

/// Lets the admin pick a saved reply (returned, to drop into the message
/// box) and add, edit or delete them.
Future<String?> showSavedRepliesSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: _sheetShape,
    builder: (_) => const _SavedRepliesSheet(),
  );
}

class _SavedRepliesSheet extends StatefulWidget {
  const _SavedRepliesSheet();

  @override
  State<_SavedRepliesSheet> createState() => _SavedRepliesSheetState();
}

class _SavedRepliesSheetState extends State<_SavedRepliesSheet> {
  List<SavedReply>? _replies;
  String? _error;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final replies = await context.read<AppState>().supportTools.savedReplies();
      if (mounted) setState(() => _replies = replies);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit([SavedReply? existing]) async {
    final title = TextEditingController(text: existing?.title);
    final body = TextEditingController(text: existing?.body);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(existing == null ? 'New saved reply' : 'Edit saved reply', style: AppTextStyles.heading(color: AppColors.navy, size: 17)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, style: _body(), cursorColor: AppColors.navy, decoration: _fieldDecoration('Title, e.g. Refund timeline')),
              const SizedBox(height: 10),
              TextField(
                controller: body,
                minLines: 3,
                maxLines: 8,
                style: _body(),
                cursorColor: AppColors.navy,
                decoration: _fieldDecoration('The reply text'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel', style: _body(weight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Save', style: _body(weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final tools = context.read<AppState>().supportTools;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (existing == null) {
        await tools.createSavedReply(title.text.trim(), body.text.trim());
      } else {
        await tools.updateSavedReply(existing.id, title.text.trim(), body.text.trim());
      }
      await _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(SavedReply reply) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().supportTools.deleteSavedReply(reply.id);
      await _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final replies = (_replies ?? const <SavedReply>[])
        .where((r) => query.isEmpty || r.title.toLowerCase().contains(query) || r.body.toLowerCase().contains(query))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: (MediaQuery.of(context).size.height * 0.7).clamp(0.0, 620.0).toDouble(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Saved replies', style: AppTextStyles.heading(color: AppColors.navy, size: 18))),
                    TextButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add_rounded, color: AppColors.navy, size: 18),
                      label: Text('New', style: _body(weight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: _body(),
                  cursorColor: AppColors.navy,
                  decoration: _fieldDecoration('Search saved replies').copyWith(
                    prefixIcon: Icon(Icons.search_rounded, color: AppColors.navy.withValues(alpha: 0.5)),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _error != null
                      ? Center(child: Text(_error!, style: _body(alpha: 0.7)))
                      : _replies == null
                          ? const Center(child: CircularProgressIndicator(color: AppColors.navy))
                          : replies.isEmpty
                              ? Center(
                                  child: Text(
                                    _replies!.isEmpty ? 'No saved replies yet — add the answers you give most often.' : 'No matches.',
                                    textAlign: TextAlign.center,
                                    style: _body(alpha: 0.6),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: replies.length,
                                  separatorBuilder: (_, _) => const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final reply = replies[index];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(reply.title, style: _body(weight: FontWeight.w700)),
                                      subtitle: Text(reply.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: _body(size: 12.5, alpha: 0.65)),
                                      onTap: () => Navigator.of(context).pop(reply.body),
                                      trailing: PopupMenuButton<String>(
                                        color: Colors.white,
                                        icon: Icon(Icons.more_vert_rounded, color: AppColors.navy.withValues(alpha: 0.6)),
                                        onSelected: (action) => action == 'edit' ? _edit(reply) : _delete(reply),
                                        itemBuilder: (_) => [
                                          PopupMenuItem(value: 'edit', child: Text('Edit', style: _body())),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete', style: AppTextStyles.body(color: const Color(0xFFB42318), size: 14)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Customer context ------------------------------------------------------------

/// The customer on the other end: who they are, their recent bookings,
/// payments, reports and other support chats.
Future<void> showCustomerContextSheet(BuildContext context, String threadId) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: _sheetShape,
    builder: (_) => _CustomerContextSheet(threadId: threadId),
  );
}

class _CustomerContextSheet extends StatefulWidget {
  const _CustomerContextSheet({required this.threadId});
  final String threadId;

  @override
  State<_CustomerContextSheet> createState() => _CustomerContextSheetState();
}

class _CustomerContextSheetState extends State<_CustomerContextSheet> {
  CustomerContext? _context;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().supportTools.customerContext(widget.threadId).then((c) {
      if (mounted) setState(() => _context = c);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : "Couldn't load this customer's details.");
    });
  }

  Widget _section(String title, List<Widget> rows, {String empty = 'None'}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _body(size: 13, weight: FontWeight.w700, alpha: 0.75)),
          const SizedBox(height: 6),
          if (rows.isEmpty) Text(empty, style: _body(size: 13, alpha: 0.55)) else ...rows,
        ],
      ),
    );
  }

  Widget _row(String left, String right) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(left, style: _body(size: 13))),
        const SizedBox(width: 8),
        Text(right, style: _body(size: 12.5, weight: FontWeight.w600, alpha: 0.75)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = _context;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: _error != null
            ? Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: _body(alpha: 0.7)))
            : c == null
                ? const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    children: [
                      Text(c.name, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          _statusLabel(c.role),
                          'joined ${formatShortDate(c.joinedAt)}',
                          if (!c.emailVerified) 'email not verified',
                          if (c.deactivated) 'deactivated',
                        ].join(' · '),
                        style: _body(size: 12.5, alpha: 0.65),
                      ),
                      const SizedBox(height: 6),
                      Text([c.email, if (c.phone != null && c.phone!.isNotEmpty) c.phone!].join(' · '), style: _body(size: 13)),
                      if (c.shopName != null) Text('Shop: ${c.shopName}', style: _body(size: 13)),
                      if (c.role == 'LANDLORD')
                        _section('Listings', [
                          _row('${c.listingsTotal} listed', '${c.listingsOccupied} occupied'),
                          if (c.openReportsOnListings > 0) _row('Open reports on their listings', '${c.openReportsOnListings}'),
                        ]),
                      if (c.role == 'LANDLORD')
                        _section('Recent bookings on their listings', [
                          for (final b in c.landlordBookings)
                            _row('${b.propertyTitle}${b.tenantName != null ? ' — ${b.tenantName}' : ''}', _statusLabel(b.status)),
                        ])
                      else
                        _section('Recent bookings', [
                          for (final b in c.tenantBookings) _row(b.propertyTitle, _statusLabel(b.status)),
                        ]),
                      _section('Recent payments', [
                        for (final p in c.payments)
                          _row(
                            '${p.paid ? 'Paid' : 'Received'} ₦${formatNaira(p.amountKobo ~/ 100)} · ${formatShortDate(p.createdAt)}',
                            _statusLabel(p.status),
                          ),
                      ]),
                      _section('Reports', [_row('Reports they filed', '${c.reportsFiled}')]),
                      _section('Other support chats', [
                        for (final chat in c.pastChats)
                          _row(
                            '${chat.topic?.label ?? 'Support'} · ${formatShortDate(chat.createdAt)}',
                            chat.resolved ? 'Resolved' : 'Open',
                          ),
                      ]),
                    ],
                  ),
      ),
    );
  }
}

// --- Phone calls --------------------------------------------------------------

/// "Call customer": the admin gives a reason (required — it's logged with
/// this chat and in the activity log), then the call is recorded and the
/// device's dialler opens. On the website the browser hands the number to
/// whatever places calls on that computer (a linked phone, Teams, FaceTime…),
/// and the number is always shown with a Copy button in case nothing does.
/// Past calls from this chat are listed underneath.
/// [canCall] false shows only the call log (a read-only oversight view).
Future<void> showCallCustomerSheet(BuildContext context, String threadId, {String? customerName, bool canCall = true}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: _sheetShape,
    builder: (_) => _CallSheet(threadId: threadId, customerName: customerName, canCall: canCall),
  );
}

class _CallSheet extends StatefulWidget {
  const _CallSheet({required this.threadId, required this.customerName, required this.canCall});
  final String threadId;
  final String? customerName;
  final bool canCall;

  @override
  State<_CallSheet> createState() => _CallSheetState();
}

class _CallSheetState extends State<_CallSheet> {
  final _reason = TextEditingController();
  List<SupportCall>? _calls;
  String? _loadError;
  String? _formError;
  bool _calling = false;

  /// Set once a call was logged — the number, shown for dialling by hand.
  String? _dialledNumber;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final calls = await context.read<AppState>().supportTools.calls(widget.threadId);
      if (mounted) setState(() => _calls = calls);
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  Future<void> _call() async {
    final reason = _reason.text.trim();
    if (reason.length < 10) {
      setState(() => _formError = 'Give a reason of at least 10 characters — it is logged with this chat.');
      return;
    }
    setState(() {
      _calling = true;
      _formError = null;
    });
    try {
      final result = await context.read<AppState>().supportTools.logCall(widget.threadId, reason);
      if (!mounted) return;
      setState(() {
        _dialledNumber = result.phoneNumber;
        _reason.clear();
      });
      unawaited(_load());
      final uri = Uri(scheme: 'tel', path: result.phoneNumber.replaceAll(RegExp(r'[^0-9+]'), ''));
      try {
        await launchUrl(uri);
      } catch (_) {
        // Nothing on this device places calls — the number is shown below.
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = _calls;
    final who = widget.customerName?.trim().isNotEmpty == true ? widget.customerName!.trim() : 'the customer';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              Text(widget.canCall ? 'Call $who' : 'Calls from this chat', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              if (widget.canCall) ...[
                const SizedBox(height: 4),
                Text(
                  'Say why you are calling. The reason, the time and your name are saved with this chat and in the activity log.',
                  style: _body(size: 13, alpha: 0.65),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  style: _body(),
                  cursorColor: AppColors.navy,
                  decoration: _fieldDecoration('Reason for calling (e.g. confirm the refund account details)').copyWith(
                    counterStyle: _body(size: 11, alpha: 0.5),
                  ),
                ),
                if (_formError != null) ...[
                  const SizedBox(height: 4),
                  Text(_formError!, style: AppTextStyles.body(color: Colors.red.shade700, size: 12.5)),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _calling ? null : _call,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.35),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    icon: _calling
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.call_rounded, color: Colors.white),
                    label: Text('Log reason and call', style: AppTextStyles.button(color: Colors.white, size: 14)),
                  ),
                ),
                if (_dialledNumber != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                    decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Call logged. If your dialler didn\'t open, dial:', style: _body(size: 12.5, alpha: 0.7)),
                              const SizedBox(height: 2),
                              SelectableText(_dialledNumber!, style: _body(size: 16, weight: FontWeight.w800)),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _dialledNumber!));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Number copied')));
                          },
                          icon: const Icon(Icons.copy_rounded, color: AppColors.navy),
                          tooltip: 'Copy number',
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text('Earlier calls', style: _body(size: 14, weight: FontWeight.w700)),
              ],
              const SizedBox(height: 8),
              if (_loadError != null)
                Text(_loadError!, style: _body(alpha: 0.7))
              else if (calls == null)
                const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: AppColors.navy)))
              else if (calls.isEmpty)
                Text('No calls from this chat yet.', style: _body(alpha: 0.6))
              else
                for (final call in calls)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(call.reason, style: _body()),
                        const SizedBox(height: 6),
                        Text(
                          '${call.adminName ?? 'A former admin'} called ${call.phoneNumber} · ${_stamp(call.createdAt)}',
                          style: _body(size: 11.5, alpha: 0.6),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
