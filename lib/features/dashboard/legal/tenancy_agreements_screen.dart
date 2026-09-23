import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/responsive.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/dashboard_theme.dart';
import '../../../state/app_state.dart';
import '../../../widgets/empty_state.dart';
import '../models/property.dart';
import '../models/rental_record.dart';
import 'tenancy_agreement_view_screen.dart';

/// Lists a tenancy agreement for every property the tenant has actually
/// rented — a shortlet booking doesn't get one, since a 3-night stay isn't a
/// lease. Reached from Settings > Support & Legal.
class TenancyAgreementsScreen extends StatelessWidget {
  const TenancyAgreementsScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final history = appState.rentalHistory;
    final entries = {for (final b in appState.myBookings) b.property.id: b.property}.values
        .where((p) => p.category != 'Shortlet' && history.containsKey(p.id))
        .toList()
      ..sort((a, b) => history[b.id]!.startDate.compareTo(history[a.id]!.startDate));

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('Tenancy Agreements', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: entries.isEmpty
              ? EmptyState(
                  theme: theme,
                  icon: Icons.description_outlined,
                  title: 'No tenancy agreements yet',
                  message:
                      'Once you successfully rent a property, its tenancy agreement will appear here for you to view and download.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    for (final property in entries)
                      _AgreementTile(theme: theme, property: property, record: history[property.id]!),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AgreementTile extends StatelessWidget {
  const _AgreementTile({required this.theme, required this.property, required this.record});

  final DashboardTheme theme;
  final Property property;
  final RentalRecord record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TenancyAgreementViewScreen(theme: theme, property: property, record: record)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: theme.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(Icons.gavel_rounded, color: theme.accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: theme.onSurface, size: 14.5, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tenancy Agreement · ${property.location}',
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.6), size: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}
