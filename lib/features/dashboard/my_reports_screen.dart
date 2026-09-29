import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/reports_repository.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';

/// Settings > My Reports: every listing or item the user reported and where
/// each stands. Text is theme.foreground on theme.background; each report
/// sits on the surface/onSurface pair.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  List<MyReport>? _reports;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reports = await context.read<AppState>().reports.mine();
      if (mounted) setState(() => _reports = reports);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final reports = _reports;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('My Reports', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: AppTextStyles.body(color: theme.foreground)))
          : reports == null
          ? Center(child: CircularProgressIndicator(color: theme.foreground))
          : reports.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  "You haven't reported anything. If a listing or item looks wrong, use \"Report\" on its page.",
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.75), size: 14),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: reports.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final report = reports[index];
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                report.subject ?? 'Removed listing',
                                style: AppTextStyles.body(color: theme.onSurface, size: 14.5, weight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              report.statusLabel,
                              style: AppTextStyles.body(color: theme.onSurface, size: 12, weight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(report.reason, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.8), size: 13)),
                        const SizedBox(height: 6),
                        Text(
                          'Sent ${formatShortDate(report.createdAt.toLocal())}',
                          style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 11.5),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
