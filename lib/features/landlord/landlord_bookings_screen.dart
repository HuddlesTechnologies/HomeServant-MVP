import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../dashboard/notifications_screen.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/upload_picker.dart';
import 'widgets/landlord_widgets.dart';

enum _Outcome { pending, accepted, declined }

class _PendingBooking {
  _PendingBooking({required this.name, required this.propertyType});

  final String name;
  final String propertyType;
  _Outcome outcome = _Outcome.pending;
}

class _RentEntry {
  _RentEntry({required this.name, required this.propertyType, required this.dateRange});

  final String name;
  final String propertyType;
  final String dateRange;
  _Outcome outcome = _Outcome.pending;
}

List<_PendingBooking> _seedBookings() => [
  _PendingBooking(name: 'Jenifer Oreoluwa Edoh', propertyType: '2 Room Bedroom Apartment'),
  _PendingBooking(name: 'Michael Kennedy', propertyType: 'BQ Apartment'),
  _PendingBooking(name: 'Efosa Adebayo', propertyType: '2 Room Bedroom Apartment'),
];

List<_RentEntry> _seedRent() => [
  _RentEntry(name: 'Stephen Osi', propertyType: '2 Bedroom Apartment', dateRange: 'May 2026 - May 2027'),
  _RentEntry(name: 'Stephen Osi', propertyType: '4 Bedroom Apartment', dateRange: 'May 2026 - May 2027'),
];

/// Bookings tab of the redesigned landlord dashboard: pending booking
/// requests a landlord can accept/decline, plus a running list of signed
/// rent agreements. Accepting/declining doesn't delete the entry — it moves
/// to "resolved", still visible (with its outcome) from "See all", so that
/// link is a real history view rather than a dead end.
class LandlordBookingsScreen extends StatefulWidget {
  const LandlordBookingsScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  State<LandlordBookingsScreen> createState() => _LandlordBookingsScreenState();
}

class _LandlordBookingsScreenState extends State<LandlordBookingsScreen> {
  late final List<_PendingBooking> _bookings = _seedBookings();
  late final List<_RentEntry> _rent = _seedRent();

  void _respond(_PendingBooking booking, {required bool accepted}) {
    setState(() => booking.outcome = accepted ? _Outcome.accepted : _Outcome.declined);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(accepted ? 'Booking with ${booking.name} accepted' : 'Booking with ${booking.name} declined'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _respondRent(_RentEntry entry, {required bool accepted}) {
    setState(() => entry.outcome = accepted ? _Outcome.accepted : _Outcome.declined);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(accepted ? 'Rent renewal for ${entry.name} approved' : 'Rent renewal for ${entry.name} declined'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openBookingHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HistoryListScreen(
          title: 'All Bookings',
          rows: [
            for (final b in _bookings) _HistoryRow(name: b.name, subtitle: b.propertyType, outcome: b.outcome),
          ],
        ),
      ),
    );
  }

  void _openRentHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HistoryListScreen(
          title: 'Rent Roll',
          rows: [
            for (final r in _rent)
              _HistoryRow(name: r.name, subtitle: '${r.propertyType} • ${r.dateRange}', outcome: r.outcome),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final photoPath = context.watch<AppState>().profilePhotoPath;
    final pendingBookings = _bookings.where((b) => b.outcome == _Outcome.pending).toList();
    final pendingRent = _rent.where((r) => r.outcome == _Outcome.pending).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.hintGrey.withValues(alpha: 0.2),
                    image: photoPath != null
                        ? DecorationImage(image: imageProviderForPath(photoPath), fit: BoxFit.cover)
                        : null,
                  ),
                  child: photoPath == null
                      ? Icon(Icons.person_rounded, color: theme.foreground.withValues(alpha: 0.6))
                      : null,
                ),
                NotificationBell(
                  color: theme.foreground,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => NotificationsScreen(theme: theme)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LandlordSectionPill(icon: HouseBookingIcon(color: AppColors.gold, size: 20), label: 'Bookings'),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      HouseBookingIcon(color: AppColors.gold, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Upcoming Bookings',
                        style: AppTextStyles.body(color: AppColors.gold, size: 15, weight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (pendingBookings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No pending bookings.',
                        style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 13),
                      ),
                    )
                  else
                    for (final booking in pendingBookings)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const LandlordAvatar(radius: 18, background: AppColors.sand, iconColor: AppColors.navy),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    booking.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(color: Colors.white, size: 14, weight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${booking.propertyType} •',
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            LandlordAcceptRejectButtons(
                              onAccept: () => _respond(booking, accepted: true),
                              onReject: () => _respond(booking, accepted: false),
                            ),
                          ],
                        ),
                      ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: _openBookingHistory,
                      child: Text(
                        'See all',
                        style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.7), size: 12.5, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            LandlordSectionPill(
              icon: const Icon(Icons.receipt_long_rounded, color: AppColors.gold, size: 20),
              label: 'Rent',
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.receipt_long_rounded, color: AppColors.gold, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'Rent',
                            style: AppTextStyles.body(color: AppColors.gold, size: 15, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: _openRentHistory,
                        child: Row(
                          children: [
                            Text(
                              'See all',
                              style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.7), size: 12.5, weight: FontWeight.w600),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_rounded, color: Colors.white.withValues(alpha: 0.7), size: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (pendingRent.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No rent entries.',
                        style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 13),
                      ),
                    )
                  else
                    for (final entry in pendingRent)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const LandlordAvatar(radius: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.name,
                                    style: AppTextStyles.body(color: AppColors.gold, size: 13.5, weight: FontWeight.w700),
                                  ),
                                  Text(
                                    entry.propertyType,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
                                  ),
                                  Text(
                                    entry.dateRange,
                                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            LandlordAcceptRejectButtons(
                              onAccept: () => _respondRent(entry, accepted: true),
                              onReject: () => _respondRent(entry, accepted: false),
                            ),
                          ],
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

class _HistoryRow {
  const _HistoryRow({required this.name, required this.subtitle, required this.outcome});

  final String name;
  final String subtitle;
  final _Outcome outcome;
}

/// Read-only "See all" destination for both Bookings and Rent — every
/// entry (pending, accepted, and declined) with a status badge, so nothing
/// that's been acted on just disappears.
class _HistoryListScreen extends StatelessWidget {
  const _HistoryListScreen({required this.title, required this.rows});

  final String title;
  final List<_HistoryRow> rows;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
        title: Text(title, style: AppTextStyles.heading(color: AppColors.gold, size: 18)),
      ),
      body: SafeArea(
        child: rows.isEmpty
            ? Center(
                child: Text(
                  'Nothing here yet.',
                  style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6)),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: rows.length,
                itemBuilder: (context, index) => _HistoryTile(row: rows[index]),
              ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row});

  final _HistoryRow row;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (row.outcome) {
      _Outcome.pending => ('Pending', AppColors.gold),
      _Outcome.accepted => ('Accepted', const Color(0xFF3FBF6A)),
      _Outcome.declined => ('Declined', const Color(0xFFE0554F)),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const LandlordAvatar(radius: 18, background: AppColors.sand, iconColor: AppColors.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.name, style: AppTextStyles.body(color: Colors.white, size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  row.subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: AppTextStyles.body(color: color, size: 11, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
