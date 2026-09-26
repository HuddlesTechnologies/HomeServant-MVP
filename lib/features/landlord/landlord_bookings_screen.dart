import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/booking.dart' as api;
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/confirm_sheet.dart';
import '../dashboard/notifications_screen.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/upload_picker.dart';
import 'tenant_profile_view_screen.dart';
import 'widgets/landlord_widgets.dart';

enum _Outcome { pending, accepted, declined }

_Outcome _outcomeOf(api.BookingStatus status) => switch (status) {
  api.BookingStatus.pending => _Outcome.pending,
  api.BookingStatus.declined => _Outcome.declined,
  // PAID/MOVED_IN/REFUNDED (and, for a non-Shortlet rental, every stage
  // between payment and move-in — paidAwaitingInspection/
  // inspectionProposed/inspectionConfirmed) all started with the booking
  // going through — this history view only distinguishes
  // pending/accepted/declined, so every later stage still reads as
  // "accepted" here.
  api.BookingStatus.accepted ||
  api.BookingStatus.paid ||
  api.BookingStatus.paidAwaitingInspection ||
  api.BookingStatus.inspectionProposed ||
  api.BookingStatus.inspectionConfirmed ||
  api.BookingStatus.movedIn ||
  api.BookingStatus.refunded =>
    _Outcome.accepted,
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
    final tenantName = booking.tenantName ?? 'tenant';
    // For a non-Shortlet property, "accepted" specifically means the
    // inspection date the tenant proposed is now confirmed — the booking
    // itself isn't accepted/rejected until later (pay/moved-in/refund).
    final isInspection = !booking.isShortlet;
    try {
      await appState.respondToBooking(booking.id, accepted: accepted);
      final message = accepted
          ? (isInspection ? 'Inspection date confirmed with $tenantName' : 'Booking with $tenantName accepted')
          : (isInspection ? 'Inspection request from $tenantName declined' : 'Booking with $tenantName declined');
      messenger.showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Landlord accepts/declines the tenant's specific proposed inspection
  /// date — distinct from [_rejectBooking], which ends the booking
  /// outright.
  Future<void> _respondToInspection(api.Booking booking, {required bool accepted}) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final tenantName = booking.tenantName ?? 'tenant';
    try {
      await appState.respondToInspection(booking.id, accepted: accepted);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            accepted ? 'Inspection date confirmed with $tenantName' : 'Inspection date declined — $tenantName can propose another',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// The landlord's distinct "reject this booking outright" lever — full
  /// refund, no platform fee withheld, ending the booking terminally. Kept
  /// visually and behaviorally separate from declining just an inspection
  /// date (see [_respondToInspection]), since this is a much bigger
  /// decision — it can't be undone and the tenant would have to book again
  /// from scratch.
  Future<void> _rejectBooking(api.Booking booking) async {
    final tenantName = booking.tenantName ?? 'this tenant';
    final confirmed = await showConfirmSheet(
      context,
      title: 'Reject this booking outright?',
      body:
          "This fully refunds $tenantName — no platform fee withheld — and ends the booking for good. This is "
          "different from declining a single inspection date: $tenantName would need to book again from scratch "
          "if they still want this property. This can't be undone.",
      actionLabel: 'Reject & Refund in Full',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await appState.rejectBooking(booking.id);
      messenger.showSnackBar(SnackBar(content: Text('Booking with $tenantName rejected — refunded in full')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _openTenantProfile(api.Booking booking) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TenantProfileViewScreen(booking: booking)));
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

  void _openRentHistory(List<api.Booking> rented) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _HistoryListScreen(
          title: 'Rent Roll',
          rows: [
            for (final b in rented)
              _HistoryRow(
                name: b.tenantName ?? 'Tenant',
                subtitle: '${b.property.title} • ${_rentSubtitle(b)}',
                outcome: _Outcome.accepted,
              ),
          ],
        ),
      ),
    );
  }

  /// Builds "since ..., expires ..., last paid ..." from the booking's
  /// lease-start, lease-end, and last-payment dates, falling back
  /// gracefully wherever a piece is missing (e.g. a Shortlet booking,
  /// which has no lease dates).
  String _rentSubtitle(api.Booking b) {
    final parts = <String>[];
    if (b.leaseStartDate != null) parts.add('since ${formatShortDate(b.leaseStartDate!)}');
    if (b.leaseEndDate != null) parts.add('expires ${formatShortDate(b.leaseEndDate!)}');
    if (b.lastPaidAt != null) parts.add('last paid ${formatShortDate(b.lastPaidAt!)}');
    if (parts.isEmpty) return 'since ${formatShortDate(b.createdAt)}';
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final appState = context.watch<AppState>();
    final photoPath = appState.profilePhotoPath;
    final allBookings = appState.landlordBookings;
    final pendingBookings = allBookings.where((b) => b.status == api.BookingStatus.pending).toList();
    // MOVED_IN (non-Shortlet) / PAID (Shortlet) are the only statuses that
    // mean "currently paying rent on this property" — BookingStatus.accepted
    // is only ever a Shortlet's pre-payment approval step, so filtering on
    // it here (as this used to) meant a tenant who'd actually moved in and
    // paid never showed up in "Rent" at all.
    const rentedStatuses = {api.BookingStatus.movedIn, api.BookingStatus.paid};
    final rentedBookings = allBookings.where((b) => rentedStatuses.contains(b.status)).toList();
    // A non-Shortlet rental between payment and move-in — this is where an
    // inspection date gets proposed/confirmed, and where the landlord's
    // distinct outright-rejection lever lives (see _rejectBooking).
    const activeStatuses = {
      api.BookingStatus.paidAwaitingInspection,
      api.BookingStatus.inspectionProposed,
      api.BookingStatus.inspectionConfirmed,
    };
    final activeRentals = allBookings.where((b) => activeStatuses.contains(b.status)).toList();

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
                  showDot: context.watch<AppState>().unreadNotificationCount > 0,
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
                                    booking.isShortlet
                                        ? '${booking.property.title} •'
                                        // A non-Shortlet booking only ever sits PENDING for the
                                        // brief moment between creation and its immediate charge
                                        // landing — `respond` is Shortlet-only now, so there's no
                                        // landlord action here, just a status note.
                                        : '${booking.property.title} • payment in progress',
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () => _openTenantProfile(booking),
                              tooltip: 'View Tenant Profile',
                              icon: const Icon(Icons.badge_outlined, color: AppColors.gold, size: 20),
                            ),
                            if (booking.isShortlet)
                              LandlordAcceptRejectButtons(
                                onAccept: () => _respond(booking, accepted: true),
                                onReject: () => _respond(booking, accepted: false),
                                acceptTooltip: 'Accept booking',
                                rejectTooltip: 'Decline booking',
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
              icon: const Icon(Icons.verified_user_rounded, color: AppColors.gold, size: 20),
              label: 'Inspections & Active Rentals',
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (activeRentals.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No active rentals awaiting an inspection or move-in.',
                        style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 13),
                      ),
                    )
                  else
                    for (final booking in activeRentals)
                      _ActiveRentalTile(
                        booking: booking,
                        onViewProfile: () => _openTenantProfile(booking),
                        onConfirmInspection: () => _respondToInspection(booking, accepted: true),
                        onDeclineInspection: () => _respondToInspection(booking, accepted: false),
                        onReject: () => _rejectBooking(booking),
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
                        onTap: () => _openRentHistory(rentedBookings),
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
                  if (rentedBookings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No rent entries.',
                        style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 13),
                      ),
                    )
                  else
                    for (final entry in rentedBookings.take(5))
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
                                    _rentSubtitle(entry),
                                    overflow: TextOverflow.ellipsis,
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

/// One row in the "Inspections & Active Rentals" card — a non-Shortlet
/// booking somewhere between payment and move-in. Carries three
/// deliberately distinct actions: "View Tenant Profile" (always available,
/// a plain icon button), Confirm/Decline of a specific proposed inspection
/// date (only while one is pending — the same small check/cross icon pair
/// used for a Shortlet's initial accept/decline), and, visually and
/// behaviorally separate from both, a full-width "Reject Booking" pill at
/// the bottom — the landlord's much bigger, terminal, no-fee-refund
/// decision, styled and placed so it's never mistaken for just declining a
/// date.
class _ActiveRentalTile extends StatelessWidget {
  const _ActiveRentalTile({
    required this.booking,
    required this.onViewProfile,
    required this.onConfirmInspection,
    required this.onDeclineInspection,
    required this.onReject,
  });

  final api.Booking booking;
  final VoidCallback onViewProfile;
  final VoidCallback onConfirmInspection;
  final VoidCallback onDeclineInspection;
  final VoidCallback onReject;

  String get _statusLine => switch (booking.status) {
    api.BookingStatus.paidAwaitingInspection => 'Paid — waiting for an inspection date to be proposed',
    api.BookingStatus.inspectionProposed => booking.requestedDate != null
        ? 'Wants inspection on ${formatShortDate(booking.requestedDate!)}'
        : 'Proposed an inspection date',
    api.BookingStatus.inspectionConfirmed => booking.requestedDate != null
        ? 'Inspection confirmed for ${formatShortDate(booking.requestedDate!)}'
        : 'Inspection confirmed',
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                      '${booking.property.title} • $_statusLine',
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onViewProfile,
                tooltip: 'View Tenant Profile',
                icon: const Icon(Icons.badge_outlined, color: AppColors.gold, size: 20),
              ),
              if (booking.status == api.BookingStatus.inspectionProposed)
                LandlordAcceptRejectButtons(
                  onAccept: onConfirmInspection,
                  onReject: onDeclineInspection,
                  acceptTooltip: 'Confirm this inspection date',
                  rejectTooltip: 'Decline this date',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onReject,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE0554F), width: 1.2),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              icon: const Icon(Icons.block_rounded, color: Color(0xFFE0554F), size: 16),
              label: Text(
                'Reject Booking',
                style: AppTextStyles.body(color: const Color(0xFFE0554F), size: 12, weight: FontWeight.w700),
              ),
            ),
          ),
        ],
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
