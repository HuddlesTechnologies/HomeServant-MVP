import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../api/api_exception.dart';
import '../../../api/models/verification.dart';
import '../../../core/date_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../state/app_state.dart';
import '../../../widgets/labeled_value_row.dart';
import 'admin_badge.dart';

const _red = Color(0xFFC53030);
const _green = Color(0xFF2F855A);
const _amber = Color(0xFFB7791F);

Color verificationStatusColor(VerificationStatus? status) => switch (status) {
  VerificationStatus.approved => _green,
  VerificationStatus.rejected => _red,
  VerificationStatus.pending => _amber,
  _ => AppColors.hintGrey,
};

/// "Identity verification" on an admin's user detail page: the full ID
/// number, the landlord's certificate and document (short-lived signed
/// links from the private bucket), and Approve / Reject while pending.
/// Moderators and super admins only (the API enforces the same). White
/// card, navy text.
class AdminVerificationCard extends StatefulWidget {
  const AdminVerificationCard({super.key, required this.userId, required this.isLandlord});

  final String userId;
  final bool isLandlord;

  @override
  State<AdminVerificationCard> createState() => _AdminVerificationCardState();
}

class _AdminVerificationCardState extends State<AdminVerificationCard> {
  VerificationDetail? _detail;
  String? _error;
  DateTime? _loadedAt;

  bool get _canView => context.read<AppState>().adminLevel?.atLeastModerator ?? false;

  @override
  void initState() {
    super.initState();
    if (_canView) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await context.read<AppState>().verification.detail(widget.userId);
      if (mounted) {
        setState(() {
          _detail = detail;
          _loadedAt = DateTime.now();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Signed links stop working after a few minutes; fetch fresh ones first
  /// if these are old.
  Future<void> _open(String? Function(VerificationDetail d) pick) async {
    final loadedAt = _loadedAt;
    final detail = _detail;
    if (detail == null) return;
    final stale = loadedAt == null || DateTime.now().difference(loadedAt).inSeconds > detail.linksExpireInSeconds - 60;
    if (stale) await _load();
    final url = _detail == null ? null : pick(_detail!);
    if (url == null) return;
    final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the document")));
    }
  }

  Future<void> _decide(bool approve) async {
    final decided = await showModalBottomSheet<VerificationDetail>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _DecisionSheet(userId: widget.userId, approve: approve),
    );
    if (decided != null && mounted) {
      setState(() {
        _detail = decided;
        _loadedAt = DateTime.now();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Identity Verification', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
              ),
              if (d != null)
                AdminBadge(
                  text: d.status?.label ?? 'Not submitted',
                  color: verificationStatusColor(d.status),
                ),
              if (_canView)
                IconButton(
                  onPressed: _load,
                  tooltip: 'Refresh',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.navy, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_canView)
            Text(
              'Only moderators and super admins can view identity documents.',
              style: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
            )
          else if (_error != null)
            Text(_error!, style: AppTextStyles.body(color: _red, size: 13))
          else if (d == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(color: AppColors.navy)),
            )
          else if (d.status == null)
            Text(
              'This user has not submitted identity documents. (Accounts created before this was required will not have any.)',
              style: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
            )
          else ...[
            LabeledValueRow('Means of ID', d.idType?.label ?? 'Not given'),
            LabeledValueRow('ID Number', d.idNumber ?? 'Not given'),
            if (d.submittedAt != null) LabeledValueRow('Submitted', formatShortDate(d.submittedAt!)),
            if (widget.isLandlord) ...[
              const SizedBox(height: 10),
              _DocumentTile(
                label: 'Certificate of Ownership',
                url: d.certificateUrl,
                isPdf: d.certificateIsPdf,
                onOpen: () => _open((x) => x.certificateUrl),
              ),
              const SizedBox(height: 10),
              _DocumentTile(
                label: 'Supporting Document',
                url: d.documentUrl,
                isPdf: d.documentIsPdf,
                onOpen: () => _open((x) => x.documentUrl),
              ),
              const SizedBox(height: 6),
              Text(
                'Document links are private and expire after ${d.linksExpireInSeconds ~/ 60} minutes; they refresh when you open them.',
                style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
              ),
            ],
            if (d.reviewedAt != null) ...[
              const SizedBox(height: 10),
              LabeledValueRow(
                d.status == VerificationStatus.approved ? 'Verified by' : 'Reviewed by',
                '${d.reviewedBy?.name ?? 'an admin'}, ${formatShortDate(d.reviewedAt!)}',
              ),
              if (d.reviewNote != null) LabeledValueRow('Note', d.reviewNote!),
            ],
            if (d.status == VerificationStatus.incomplete)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Signup was not finished, so this can\'t be reviewed yet.',
                  style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
                ),
              ),
            if (d.status == VerificationStatus.pending) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.navy),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () => _decide(false),
                      child: Text('Reject', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () => _decide(true),
                      child: Text('Verify', style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A preview of an uploaded file: the image itself, or a PDF row. Tapping
/// opens it full size in a new tab.
class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.label, required this.url, required this.isPdf, required this.onOpen});

  final String label;
  final String? url;
  final bool isPdf;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final link = url;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5, weight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (link == null)
          Text('Not uploaded', style: AppTextStyles.body(color: AppColors.navy, size: 13))
        else if (isPdf)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.navy),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: onOpen,
            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.navy, size: 18),
            label: Text('Open PDF', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 13)),
          )
        else
          InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: AppColors.offWhite,
                constraints: const BoxConstraints(maxHeight: 220),
                width: double.infinity,
                child: Image.network(
                  link,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Preview unavailable. Tap to open.', style: AppTextStyles.body(color: AppColors.navy, size: 13)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({required this.userId, required this.approve});

  final String userId;
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
      setState(() => _error = 'Tell the user what to fix (at least 10 characters). They see this.');
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await context.read<AppState>().verification.review(widget.userId, approve: widget.approve, note: note);
      navigator.pop(result);
      messenger.showSnackBar(SnackBar(content: Text(widget.approve ? 'Identity verified' : 'Verification rejected; the user was told why')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final approve = widget.approve;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(approve ? 'Verify this identity?' : 'Reject these documents?', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
            const SizedBox(height: 8),
            Text(
              approve
                  ? 'Confirm the ID number and documents match this person. They will be notified that they are verified.'
                  : 'The user is notified and emailed with your note so they know what to fix.',
              style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              style: AppTextStyles.body(color: AppColors.navy),
              decoration: InputDecoration(
                hintText: approve ? 'Internal note (optional)' : 'What needs fixing (required)',
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
                  backgroundColor: approve ? _green : AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Text(approve ? 'Verify' : 'Reject', style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
