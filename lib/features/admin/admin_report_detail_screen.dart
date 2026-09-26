import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'admin_property_detail_screen.dart';
import 'admin_user_detail_screen.dart';
import 'admin_vendor_detail_screen.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_picker_sheet.dart';

/// Full report detail — reached by tapping a row in AdminReportsTab or the
/// dashboard's activity feed. Owns the status/transfer actions that used to
/// live in AdminReportsTab's bottom sheet, plus links out to the reported
/// property/vendor and the reporter's own profile — "every possibly needed
/// info for that section."
class AdminReportDetailScreen extends StatefulWidget {
  const AdminReportDetailScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<AdminReportDetailScreen> createState() => _AdminReportDetailScreenState();
}

class _AdminReportDetailScreenState extends State<AdminReportDetailScreen> {
  AdminReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final report = await context.read<AppState>().admin.reportDetail(widget.reportId);
      if (!mounted) return;
      setState(() {
        _report = report;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load this report.");
    }
  }

  Future<void> _setStatus(AdminReport report, ReportStatus status) async {
    if (status == report.status) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.setReportStatus(report.id, status);
      messenger.showSnackBar(SnackBar(content: Text('Marked ${status.label}')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _transfer(AdminReport report) async {
    final messenger = ScaffoldMessenger.of(context);
    List<AdminAccount> admins;
    try {
      admins = await context.read<AppState>().admin.findAdmins();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    final myId = context.read<AppState>().userId;
    final chosen = await showAdminPickerSheet(
      context,
      admins: admins,
      title: 'Transfer report to',
      excludeAdminIds: {if (myId != null) myId, if (report.assignedAdmin != null) report.assignedAdmin!.id},
    );
    if (chosen == null || !mounted) return;
    try {
      await context.read<AppState>().admin.transferReport(report.id, chosen.id);
      messenger.showSnackBar(SnackBar(content: Text('Transferred to ${chosen.email}')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openReporter(String userId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserDetailScreen(userId: userId)));
  }

  void _openProperty(String propertyId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPropertyDetailScreen(propertyId: propertyId)));
  }

  void _openVendor(String vendorId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminVendorDetailScreen(vendorId: vendorId)));
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Report Details', style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: report == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(report.targetLabel, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
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
                        const SizedBox(height: 14),
                        _Field('Reason', report.reason),
                        _Field('Filed', formatShortDate(report.createdAt)),
                        _Field('Reporter', report.reporter?.displayName ?? 'Unknown'),
                        _Field('Assigned To', report.assignedAdmin?.displayName ?? 'Unassigned'),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (report.reporter != null)
                              OutlinedButton.icon(
                                onPressed: () => _openReporter(report.reporter!.id),
                                icon: const Icon(Icons.person_outline_rounded, color: AppColors.navy, size: 16),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.navy)),
                                label: Text('View Reporter', style: AppTextStyles.button(color: AppColors.navy, size: 12.5)),
                              ),
                            if (report.propertyId != null)
                              OutlinedButton.icon(
                                onPressed: () => _openProperty(report.propertyId!),
                                icon: const Icon(Icons.apartment_rounded, color: AppColors.navy, size: 16),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.navy)),
                                label: Text('View Listing', style: AppTextStyles.button(color: AppColors.navy, size: 12.5)),
                              ),
                            if (report.vendorId != null)
                              OutlinedButton.icon(
                                onPressed: () => _openVendor(report.vendorId!),
                                icon: const Icon(Icons.storefront_outlined, color: AppColors.navy, size: 16),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.navy)),
                                label: Text("View Vendor's Shop", style: AppTextStyles.button(color: AppColors.navy, size: 12.5)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Status', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 13)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final status in ReportStatus.values)
                              AdminFilterChip(
                                label: status.label,
                                selected: status == report.status,
                                onTap: () => _setStatus(report, status),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _transfer(report),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: AppColors.navy),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.navy),
                            label: Text('Transfer to another admin', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600)),
          ),
        ],
      ),
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
