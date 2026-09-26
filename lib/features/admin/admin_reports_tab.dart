import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/admin_models.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'admin_report_detail_screen.dart';
import 'widgets/admin_filter_chip.dart';

/// Reports submitted against a property or marketplace listing —
/// `findReports` (admin_repository.dart) and `AdminReport`/`ReportStatus`
/// (admin_models.dart) already exist; this screen is purely wiring them up
/// into a list. Every admin tier can view, re-status, and transfer a
/// report (see AdminReportDetailScreen, reached by tapping a row) —
/// `ReportsController` has no `@MinAdminLevel` gate on any of its
/// endpoints, unlike vendor/property moderation.
class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({super.key});

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  List<AdminReport>? _reports;
  ReportStatus? _statusFilter;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await context.read<AppState>().admin.findReports(status: _statusFilter);
      if (!mounted) return;
      setState(() {
        _reports = page.items;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load reports.");
    }
  }

  void _openDetail(AdminReport report) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminReportDetailScreen(reportId: report.id)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Column(
      children: [
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              AdminFilterChip(label: 'All', selected: _statusFilter == null, onTap: () => setState(() { _statusFilter = null; _load(); })),
              const SizedBox(width: 8),
              AdminFilterChip(label: 'Open', selected: _statusFilter == ReportStatus.open, onTap: () => setState(() { _statusFilter = ReportStatus.open; _load(); })),
              const SizedBox(width: 8),
              AdminFilterChip(label: 'In Progress', selected: _statusFilter == ReportStatus.inProgress, onTap: () => setState(() { _statusFilter = ReportStatus.inProgress; _load(); })),
              const SizedBox(width: 8),
              AdminFilterChip(label: 'Resolved', selected: _statusFilter == ReportStatus.resolved, onTap: () => setState(() { _statusFilter = ReportStatus.resolved; _load(); })),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: reports == null
              ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
              : reports.isEmpty
                  ? const Center(child: Text('No reports found'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: reports.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final report = reports[index];
                          return InkWell(
                            onTap: () => _openDetail(report),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: adminCardDecoration,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          report.targetLabel,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _StatusBadge(status: report.status),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    report.targetType == ReportTargetType.property ? 'Property' : 'Marketplace item',
                                    style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5, weight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    report.reason,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(color: AppColors.navy, size: 13),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Reported by ${report.reporter?.displayName ?? 'Unknown'}',
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTextStyles.body(color: AppColors.hintGrey, size: 12),
                                        ),
                                      ),
                                      Text(formatShortDate(report.createdAt), style: AppTextStyles.body(color: AppColors.hintGrey, size: 12)),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    report.assignedAdmin != null ? 'Assigned to ${report.assignedAdmin!.displayName}' : 'Unassigned',
                                    style: AppTextStyles.body(
                                      color: report.assignedAdmin != null ? AppColors.navy : AppColors.hintGrey,
                                      size: 12,
                                      weight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ReportStatus status;

  Color get _color => switch (status) {
    ReportStatus.open => Colors.redAccent,
    ReportStatus.inProgress => Colors.orange,
    ReportStatus.resolved => Colors.green,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
      child: Text(status.label, style: AppTextStyles.body(color: _color, size: 11, weight: FontWeight.w700)),
    );
  }
}
