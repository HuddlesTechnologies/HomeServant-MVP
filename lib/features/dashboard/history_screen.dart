import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../api/api_exception.dart';
import '../../api/models/booking.dart';
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/confirm_sheet.dart';
import '../../widgets/dashboard_page_scaffold.dart';
import '../../widgets/empty_state.dart';
import 'legal/tenancy_agreement_view_screen.dart';
import 'property_detail_screen.dart';
import 'widgets/property_image.dart';

/// The tenant's own bookings, newest first — every status (pending through
/// moved-in, declined, refunded) stays visible here with its own badge and
/// the action(s) that status allows next: for a Shortlet, pay once accepted;
/// for a non-Shortlet rental (which now charges immediately on creation),
/// propose/await/confirm an inspection date once paid, then move in or
/// refund; renew once moved in and close to lease end.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.theme});

  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final bookings = [...appState.myBookings]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: 'History',
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: 640,
          child: bookings.isEmpty
              ? EmptyState(
                  theme: theme,
                  icon: Icons.history_rounded,
                  title: 'No history yet',
                  message: 'Properties you rent or book will show up here.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    for (final booking in bookings) _HistoryTile(booking: booking, theme: theme),
                  ],
                ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({required this.booking, required this.theme});

  final Booking booking;
  final DashboardTheme theme;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _busy = false;

  /// Bookings this session has already shown the one-time "Book inspection
  /// now? / Book later / Refund" prompt for, right after they landed in
  /// PAID_AWAITING_INSPECTION — keyed by booking id so it never re-fires on
  /// rebuild, only once per booking per app session. Static so it survives
  /// this tile being rebuilt/recreated as the list reorders.
  static final Set<String> _promptedBookingIds = {};

  Booking get booking => widget.booking;
  DashboardTheme get theme => widget.theme;

  @override
  void initState() {
    super.initState();
    if (booking.status == BookingStatus.paidAwaitingInspection && _promptedBookingIds.add(booking.id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showInspectionChoicePrompt();
      });
    }
  }

  Future<void> _showInspectionChoicePrompt() async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Payment received'),
        content: const Text(
          "Your rent is held safely. Would you like to book your inspection now, do it later from History, "
          'or request a refund?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('refund'),
            child: const Text('Refund', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop('later'), child: const Text('Book Later')),
          TextButton(onPressed: () => Navigator.of(context).pop('now'), child: const Text('Book Inspection Now')),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'now':
        await _proposeInspection();
        break;
      case 'refund':
        await _performRefund();
        break;
      default:
        break;
    }
  }

  Future<void> _payRent() async {
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final payment = await appState.payForBooking(booking.id);
      final uri = Uri.parse(payment.authorizationUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        messenger.showSnackBar(const SnackBar(content: Text("Couldn't open the payment page — try again.")));
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _proposeInspection() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 3)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Choose an inspection date',
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await appState.proposeInspection(booking.id, picked);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markMovedIn() async {
    final confirmed = await showConfirmSheet(
      context,
      title: 'Confirm you\'ve moved in?',
      body:
          'This releases the held rent to the landlord and generates your tenancy agreement. This can\'t be '
          'undone — only confirm once you\'ve actually moved in.',
      actionLabel: 'Confirm Move-In',
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await appState.markBookingMovedIn(booking.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refund() async {
    final confirmed = await showConfirmSheet(
      context,
      title: 'Request a refund?',
      body: 'Your rent will be refunded, minus payment processing and platform fees (0.2%). This can\'t be undone.',
      actionLabel: 'Refund Me',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _performRefund();
  }

  /// The actual refund call, shared by the confirm-sheet-gated [_refund]
  /// button and the one-time post-payment choice prompt (which is itself
  /// already a confirmation, so it skips straight here).
  Future<void> _performRefund() async {
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await appState.refundBooking(booking.id);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _renew() async {
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await appState.renewBooking(booking.id);
      messenger.showSnackBar(const SnackBar(content: Text('Lease renewed')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final property = booking.property;
    final leaseEnd = booking.leaseEndDate;
    final withinRenewalWindow = leaseEnd != null && leaseEnd.difference(DateTime.now()).inDays <= 30;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: theme.foreground.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(
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
                        _subtitleFor(booking),
                        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _StatusBadge(status: booking.status, theme: theme),
              ],
            ),
          ),
          if (booking.status == BookingStatus.movedIn) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TenancyAgreementViewScreen(theme: theme, bookingId: booking.id)),
              ),
              child: Row(
                children: [
                  Icon(Icons.gavel_rounded, color: theme.accent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'View tenancy agreement',
                    style: AppTextStyles.body(color: theme.accent, size: 12.5, weight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
          if (booking.status != BookingStatus.pending && booking.status != BookingStatus.declined) ...[
            const SizedBox(height: 12),
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
                      rating: context.watch<AppState>().myReviewFor(property.id),
                      color: theme.accent,
                      onRate: (value) => context.read<AppState>().rateHistoryProperty(property.id, value),
                    ),
                  ],
                ),
                Flexible(child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: _actionsFor(booking, withinRenewalWindow))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _subtitleFor(Booking booking) {
    final isShortlet = booking.isShortlet;
    if (booking.status == BookingStatus.declined) {
      return 'Rejected by the landlord — refunded in full, no fee withheld';
    }
    if (booking.status == BookingStatus.refunded) {
      return 'Refunded (0.2% platform fee withheld)';
    }
    if (booking.status == BookingStatus.inspectionProposed && booking.requestedDate != null) {
      return 'Inspection proposed for ${formatShortDate(booking.requestedDate!)} — awaiting landlord';
    }
    if (booking.status == BookingStatus.inspectionConfirmed && booking.requestedDate != null) {
      return 'Inspection confirmed for ${formatShortDate(booking.requestedDate!)}';
    }
    if (booking.status == BookingStatus.paidAwaitingInspection) {
      return 'Paid — book an inspection whenever you\'re ready';
    }
    if (booking.leaseStartDate != null && booking.leaseEndDate != null) {
      return '${isShortlet ? 'Booked' : 'Leased'} ${formatShortDate(booking.leaseStartDate!)} – ${formatShortDate(booking.leaseEndDate!)}';
    }
    return '${isShortlet ? 'Booked' : 'Requested'} ${formatShortDate(booking.createdAt)}';
  }

  List<Widget> _actionsFor(Booking booking, bool withinRenewalWindow) {
    if (_busy) {
      return [const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))];
    }
    switch (booking.status) {
      case BookingStatus.accepted:
        if (booking.isShortlet && booking.property.shortletUnavailable) {
          return [
            Text(
              'Unavailable right now — payment is disabled until the current booking ends.',
              textAlign: TextAlign.right,
              style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 11.5),
            ),
          ];
        }
        return [_ActionButton(label: 'Pay Rent', theme: theme, onTap: _payRent)];
      case BookingStatus.paid:
        // Shortlet only reaches PAID (released automatically, no move-in
        // step) — a non-Shortlet booking now goes through
        // paidAwaitingInspection/inspectionProposed/inspectionConfirmed
        // instead of ever sitting at plain PAID.
        return const [];
      case BookingStatus.paidAwaitingInspection:
        return [
          _ActionButton(label: 'Refund', theme: theme, destructive: true, onTap: _refund),
          _ActionButton(label: 'Book Inspection', theme: theme, onTap: _proposeInspection),
        ];
      case BookingStatus.inspectionProposed:
        return [
          _ActionButton(label: 'Refund', theme: theme, destructive: true, onTap: _refund),
          Text(
            'Awaiting landlord response',
            style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 11.5, weight: FontWeight.w600),
          ),
        ];
      case BookingStatus.inspectionConfirmed:
        return [
          _ActionButton(label: 'Refund', theme: theme, destructive: true, onTap: _refund),
          _ActionButton(label: 'Moved In', theme: theme, onTap: _markMovedIn),
        ];
      case BookingStatus.movedIn:
        if (booking.isShortlet || !withinRenewalWindow) return const [];
        return [_ActionButton(label: 'Renew Lease', theme: theme, onTap: _renew)];
      case BookingStatus.pending:
      case BookingStatus.declined:
      case BookingStatus.refunded:
        return const [];
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.theme, required this.onTap, this.destructive = false});

  final String label;
  final DashboardTheme theme;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : theme.accent;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onTap,
      child: Text(label, style: AppTextStyles.body(color: color, size: 12.5, weight: FontWeight.w700)),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.theme});

  final BookingStatus status;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      BookingStatus.pending => ('Pending', theme.foreground.withValues(alpha: 0.5)),
      BookingStatus.accepted => ('Accepted', const Color(0xFF3FA9F5)),
      BookingStatus.paid => ('Paid', const Color(0xFFD9A94F)),
      BookingStatus.paidAwaitingInspection => ('Payment Held', const Color(0xFFD9A94F)),
      BookingStatus.inspectionProposed => ('Inspection Requested', const Color(0xFF3FA9F5)),
      BookingStatus.inspectionConfirmed => ('Inspection Confirmed', const Color(0xFF3FBF6A)),
      BookingStatus.movedIn => ('Active', Colors.green.shade600),
      BookingStatus.declined => ('Declined', Colors.redAccent),
      BookingStatus.refunded => ('Refunded', theme.foreground.withValues(alpha: 0.5)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: AppTextStyles.body(color: color, size: 11, weight: FontWeight.w700)),
    );
  }
}
