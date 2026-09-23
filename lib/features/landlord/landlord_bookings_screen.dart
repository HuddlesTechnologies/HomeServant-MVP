import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/booking.dart' as api;
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../dashboard/notifications_screen.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/upload_picker.dart';
import 'widgets/landlord_widgets.dart';

enum _Outcome { pending, accepted, declined }

_Outcome _outcomeOf(api.BookingStatus status) => switch (status) {
  api.BookingStatus.pending => _Outcome.pending,
  api.BookingStatus.accepted => _Outcome.accepted,
  api.BookingStatus.declined => _Outcome.declined,
};

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
  Future<void> _respond(api.Booking booking, {required bool accepted}) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await appState.respondToBooking(booking.id, accepted: accepted);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accepted ? 'Booking with ${booking.tenantName ?? 'tenant'} accepted' : 'Booking with ${booking.tenantName ?? 'tenant'} declined',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openBookingHistory(List<api.Booking> bookings) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HistoryListScreen(
          title: 'All Bookings',
          rows: [
            for (final b in bookings)
              _HistoryRow(name: b.tenantName ?? 'Tenant', subtitle: b.property.title, outcome: _outcomeOf(b.status)),
          ],
        ),
      ),
    );
  }

  void _openRentHistory(List<api.Booking> accepted) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HistoryListScreen(
          title: 'Rent Roll',
          rows: [
            for (final b in accepted)
              _HistoryRow(
                name: b.tenantName ?? 'Tenant',
                subtitle: '${b.property.title} • since ${formatShortDate(b.createdAt)}',
                outcome: _Outcome.accepted,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final appState = context.watch<AppState>();
    final photoPath = appState.profilePhotoPath;
    final allBookings = appState.landlordBookings;
    final pendingBookings = allBookings.where((b) => b.status == api.BookingStatus.pending).toList();
    final acceptedBookings = allBookings.where((b) => b.status == api.BookingStatus.accepted).toList();

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
                        ? DecorationImage(image: imageProviderForPath(photoPath), fit: BoxFit.contain)
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
                                    booking.tenantName ?? 'Tenant',
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(color: Colors.white, size: 14, weight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${booking.property.title} •',
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
                      onTap: () => _openBookingHistory(allBookings),
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
                        onTap: () => _openRentHistory(acceptedBookings),
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
                  if (acceptedBookings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No rent entries.',
                        style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 13),
                      ),
                    )
                  else
                    for (final entry in acceptedBookings.take(5))
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
                                    entry.tenantName ?? 'Tenant',
                                    style: AppTextStyles.body(color: AppColors.gold, size: 13.5, weight: FontWeight.w700),
                                  ),
                                  Text(
                                    entry.property.title,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
                                  ),
                                  Text(
                                    'Since ${formatShortDate(entry.createdAt)}',
                                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
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
