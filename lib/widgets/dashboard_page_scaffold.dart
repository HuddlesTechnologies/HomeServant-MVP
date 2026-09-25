import 'package:flutter/material.dart';
import '../core/theme/app_text_styles.dart';

/// Shared page shell for the dashboard/landlord screens that each used to
/// define their own identical `Scaffold(backgroundColor: ..., appBar:
/// AppBar(backgroundColor: ..., elevation: 0, iconTheme: ..., title: ...))`
/// wrapper.
///
/// Takes [background]/[foreground] directly rather than a single
/// `DashboardTheme` object: most callers pass `theme.background`/
/// `theme.foreground`, but a couple of landlord screens (Bank Details, Add
/// Property) draw fixed brand colours instead of the tenant's switchable
/// `DashboardTheme`, so a plain pair of colours is the actual common
/// denominator across every call site.
class DashboardPageScaffold extends StatelessWidget {
  const DashboardPageScaffold({
    super.key,
    required this.background,
    required this.foreground,
    required this.title,
    required this.body,
    this.actions,
  });

  final Color background;
  final Color foreground;
  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        iconTheme: IconThemeData(color: foreground),
        title: Text(title, style: AppTextStyles.heading(color: foreground, size: 18)),
        actions: actions,
      ),
      body: body,
    );
  }
}
