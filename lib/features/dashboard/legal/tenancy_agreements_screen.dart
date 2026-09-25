import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../api/models/booking.dart';
import '../../../core/responsive.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/dashboard_theme.dart';
import '../../../state/app_state.dart';
import '../../../widgets/dashboard_page_scaffold.dart';
import '../../../widgets/empty_state.dart';
import 'tenancy_agreement_view_screen.dart';

/// Lists a tenancy agreement for every booking the tenant has actually
/// moved into — a shortlet booking doesn't get one, since a few-night stay
/// isn't a lease, and PENDING/ACCEPTED/PAID bookings don't have a generated
/// agreement yet either (the backend only generates one on move-in).
/// Reached from Settings > Support & Legal.
class TenancyAgreementsScreen extends StatelessWidget {
  const TenancyAgreementsScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final entries = appState.myBookings.where((b) => !b.isShortlet && b.status == BookingStatus.movedIn).toList()
      ..sort((a, b) => (b.leaseStartDate ?? b.createdAt).compareTo(a.leaseStartDate ?? a.createdAt));

    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: 'Tenancy Agreements',
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: entries.isEmpty
              ? EmptyState(
                  theme: theme,
                  icon: Icons.description_outlined,
                  title: 'No tenancy agreements yet',
                  message:
                      'Once you move into a rented property, its tenancy agreement will appear here for you to '
                      'view and download.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    for (final booking in entries) _AgreementTile(theme: theme, booking: booking),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AgreementTile extends StatelessWidget {
  const _AgreementTile({required this.theme, required this.booking});

  final DashboardTheme theme;
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TenancyAgreementViewScreen(theme: theme, bookingId: booking.id)),
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
                      booking.property.title,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: theme.onSurface, size: 14.5, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tenancy Agreement · ${booking.property.location}',
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
