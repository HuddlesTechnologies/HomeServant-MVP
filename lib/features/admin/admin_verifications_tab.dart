import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/verification.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'admin_user_detail_screen.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_verification_card.dart';

/// Moderators and super admins: identity documents waiting for review,
/// oldest first. Tapping one opens the user's detail page, where the
/// documents are shown and the decision is made.
class AdminVerificationsTab extends StatefulWidget {
  const AdminVerificationsTab({super.key});

  @override
  State<AdminVerificationsTab> createState() => _AdminVerificationsTabState();
}

class _AdminVerificationsTabState extends State<AdminVerificationsTab> {
  static const _filters = <(String, VerificationStatus?)>[
    ('Awaiting review', VerificationStatus.pending),
    ('Verified', VerificationStatus.approved),
    ('Rejected', VerificationStatus.rejected),
    ('Incomplete', VerificationStatus.incomplete),
    ('All submitted', null),
  ];
  VerificationStatus? _status = VerificationStatus.pending;
  List<VerificationSummary>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await context.read<AppState>().verification.list(status: _status);
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
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
              child: Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body(color: const Color(0xFFC53030))),
            )
          else if (items == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                _status == VerificationStatus.pending ? 'Nothing waiting for review.' : 'Nothing here.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: AppColors.hintGrey),
              ),
            )
          else
            for (final v in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserDetailScreen(userId: v.userId)));
                      if (mounted) _load();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.user.name, style: AppTextStyles.body(color: AppColors.navy, size: 15, weight: FontWeight.w700)),
                                Text(v.user.email, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
                                const SizedBox(height: 6),
                                Text(
                                  [
                                    v.user.role == 'LANDLORD' ? 'Landlord' : 'Tenant',
                                    if (v.idType != null) '${v.idType!.label} ${v.idNumberMasked ?? ''}'.trim(),
                                    if (v.user.role == 'LANDLORD') '${(v.hasCertificate ? 1 : 0) + (v.hasDocument ? 1 : 0)}/2 documents',
                                  ].join(' · '),
                                  style: AppTextStyles.body(color: AppColors.navy, size: 12.5),
                                ),
                                // What the issuing body said, so the queue
                                // can be worked worst-first: a mismatch or
                                // a number with no record is the one to
                                // open next. "Not checked" outcomes say
                                // nothing useful here and are left out.
                                if (v.idCheckStatus.isAnswer || v.idCheckStatus == IdCheckStatus.error)
                                  Text(
                                    v.idCheckStatus.label,
                                    style: AppTextStyles.body(color: idCheckColor(v.idCheckStatus), size: 12.5, weight: FontWeight.w600),
                                  ),
                                if (v.submittedAt != null)
                                  Text(
                                    v.autoApproved
                                        ? 'Verified automatically ${formatShortDate(v.submittedAt!)}'
                                        : 'Submitted ${formatShortDate(v.submittedAt!)}',
                                    style: AppTextStyles.body(color: AppColors.hintGrey, size: 12),
                                  ),
                              ],
                            ),
                          ),
                          AdminBadge(text: v.status.label, color: verificationStatusColor(v.status)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.hintGrey),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
