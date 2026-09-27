import 'package:flutter/material.dart';
import '../../../api/models/support_tools.dart';
import '../../../core/theme/app_colors.dart';
import 'admin_badge.dart';

/// Topic and (when not Normal) priority of a support conversation, as the
/// console's tinted pills — dark text on a pale wash of the same colour.
class SupportTriageBadges extends StatelessWidget {
  const SupportTriageBadges({super.key, required this.topic, required this.priority});

  final SupportTopic? topic;
  final SupportPriority priority;

  static Color priorityColor(SupportPriority priority) => switch (priority) {
    SupportPriority.urgent => const Color(0xFFB42318),
    SupportPriority.high => const Color(0xFFB54708),
    SupportPriority.normal => AppColors.navy,
    SupportPriority.low => const Color(0xFF475467),
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (priority != SupportPriority.normal)
          AdminBadge(size: AdminBadgeSize.small, text: priority.label, color: priorityColor(priority)),
        if (topic != null) AdminBadge(size: AdminBadgeSize.small, text: topic!.label, color: AppColors.navy),
      ],
    );
  }
}
