import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/empty_state.dart';
import 'models/property.dart';
import 'models/rental_record.dart';
import 'property_detail_screen.dart';
import 'widgets/property_image.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final history = context.watch<AppState>().rentalHistory;
    final entries = mockProperties.where((p) => history.containsKey(p.id)).toList()
      ..sort((a, b) => history[b.id]!.startDate.compareTo(history[a.id]!.startDate));

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('History', style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child:
              entries.isEmpty
                  ? EmptyState(
                    theme: theme,
                    icon: Icons.history_rounded,
                    title: 'No history yet',
                    message: 'Properties you rent or book will show up here.',
                  )
                  : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      for (final property in entries)
                        _HistoryTile(property: property, record: history[property.id]!, theme: theme),
                    ],
                  ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.property, required this.record, required this.theme});

  final Property property;
  final RentalRecord record;
  final DashboardTheme theme;

  bool get _isShortlet => property.category == 'Shortlet';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: theme.foreground.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap:
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: property, theme: theme))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: PropertyImage(path: property.image, width: 72, height: 72),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.title,
                        style: AppTextStyles.body(color: theme.foreground, size: 15, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(property.location, style: AppTextStyles.body(color: theme.accent, size: 13, weight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        '${_isShortlet ? 'Booked' : 'Rented'} ${formatShortDate(record.startDate)} – ${formatShortDate(record.endDate)}',
                        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(active: record.isActive, theme: theme),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Divider(color: theme.foreground.withValues(alpha: 0.12), height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your rating', style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 12)),
                  const SizedBox(height: 4),
                  _RatingStars(
                    rating: record.rating,
                    color: theme.accent,
                    onRate: (value) => context.read<AppState>().rateHistoryProperty(property.id, value),
                  ),
                ],
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.accent, width: 1.2),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () {
                  context.read<AppState>().recordRentalOrBooking(property.id, isShortlet: _isShortlet);
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('${_isShortlet ? 'Rebooked' : 'Renewed'} ${property.title}')));
                },
                child: Text(
                  _isShortlet ? 'Rebook' : 'Renew',
                  style: AppTextStyles.body(color: theme.accent, size: 13, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active, required this.theme});

  final bool active;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.green.shade600 : theme.foreground.withValues(alpha: 0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(active ? 'Active' : 'Expired', style: AppTextStyles.body(color: color, size: 11, weight: FontWeight.w700)),
    );
  }
}

class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.rating, required this.color, required this.onRate});

  final double? rating;
  final Color color;
  final ValueChanged<double> onRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final filled = rating != null && index < rating!.round();
        return GestureDetector(
          onTap: () => onRate((index + 1).toDouble()),
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(Icons.star_rounded, color: filled ? color : color.withValues(alpha: 0.3), size: 22),
          ),
        );
      }),
    );
  }
}

