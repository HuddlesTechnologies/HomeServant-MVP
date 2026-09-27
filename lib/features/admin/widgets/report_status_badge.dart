import 'package:flutter/material.dart';
import '../../../api/models/admin_models.dart';
import 'admin_badge.dart';

/// A report's status as a colored badge — shared by the reports list and
/// a report's detail screen, which used to each define it.
class ReportStatusBadge extends StatelessWidget {
  const ReportStatusBadge({super.key, required this.status});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ReportStatus.open => Colors.redAccent,
      ReportStatus.inProgress => Colors.orange,
      ReportStatus.resolved => Colors.green,
    };
    return AdminBadge(text: status.label, color: color, size: AdminBadgeSize.large);
  }
}
