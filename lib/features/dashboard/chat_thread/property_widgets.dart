// The property or order a chat is about: the booked-property card, the tenant's booking status, and a vendor order's status banner.
part of '../chat_thread_screen.dart';

/// Formats a future date/time as "24 Oct at 10:00 AM" for the inspection
/// booking confirmation message. Deliberately kept local rather than routed
/// through `formatRelativeTime` — that helper measures elapsed time since
/// [date] (`DateTime.now().difference(date)`), which only makes sense for
/// timestamps in the past; [date] here is always a chosen future date, so
/// reusing it would show "Just now" for every booking regardless of when
/// it's actually scheduled.
String _formatScheduledDateTime(DateTime date) {
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final minute = date.minute.toString().padLeft(2, '0');
  final period = date.hour >= 12 ? 'PM' : 'AM';
  return '${date.day} ${monthAbbreviations[date.month - 1]} at $hour12:$minute $period';
}

class _OrderStatusBanner extends StatelessWidget {
  const _OrderStatusBanner({required this.theme, required this.item, required this.status});

  final DashboardTheme theme;
  final MarketplaceOrderItemApi item;
  final OrderItemStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.productName,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: status.color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Text(status.label, style: AppTextStyles.body(color: status.color, size: 11, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Pinned above the messages in a tenant–landlord chat once the tenant has
/// paid: the property's photo, name, address and price, with View property.
/// theme.surface/onSurface (a fixed pair in every DashboardTheme), and the
/// button in theme.accent/onAccent.
class _BookedPropertyCard extends StatelessWidget {
  const _BookedPropertyCard({required this.theme, required this.property, required this.onView});

  final DashboardTheme theme;
  final Property property;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final text = theme.onSurface;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PropertyImage(path: property.image, width: 64, height: 64),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(property.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(color: text, size: 14, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  _placeLine(property),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: text.withValues(alpha: 0.8), size: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '${property.priceLabel} · ${property.bedrooms} bed · ${property.bathrooms} bath',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(color: text, size: 12, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onView,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text('View property', style: AppTextStyles.body(color: theme.onAccent, size: 12, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Top of the property pop-up in a tenant's chat: where their booking of
/// this property stands, with the next step — book an inspection, wait on
/// the landlord (Pending), confirm move-in once the inspection is agreed,
/// then "rented" with a link to the tenancy agreement. Watches AppState,
/// so it updates in place (e.g. right after Moved In).
///
/// Drawn on the sheet's theme.surface: text in theme.onSurface, buttons in
/// theme.accent/onAccent, and each status colour only as a tinted pill
/// behind text of that same colour darkened for contrast.
class _TenantBookingStatusPanel extends StatefulWidget {
  const _TenantBookingStatusPanel({required this.theme, required this.propertyId, this.onBookInspection});

  final DashboardTheme theme;
  final String propertyId;

  /// Opens the in-chat inspection date picker; null hides that button.
  final VoidCallback? onBookInspection;

  @override
  State<_TenantBookingStatusPanel> createState() => _TenantBookingStatusPanelState();
}

class _TenantBookingStatusPanelState extends State<_TenantBookingStatusPanel> {
  bool _busy = false;

  DashboardTheme get theme => widget.theme;

  /// The booking that matters here: the newest one still in progress, else
  /// the newest overall (e.g. refunded).
  Booking? _bookingFrom(List<Booking> all) {
    final mine = all.where((b) => b.property.id == widget.propertyId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (mine.isEmpty) return null;
    return mine.firstWhere(
      (b) => b.status != BookingStatus.declined && b.status != BookingStatus.refunded,
      orElse: () => mine.first,
    );
  }

  Future<void> _confirmMovedIn(Booking booking) async {
    final confirmed = await showConfirmSheet(
      context,
      title: "Confirm you've moved in?",
      body:
          "This releases the held rent to the landlord and generates your tenancy agreement. This can't be "
          "undone — only confirm once you're ready and have actually moved in.",
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

  void _openAgreement(Booking booking) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => TenancyAgreementViewScreen(theme: theme, bookingId: booking.id)));

  @override
  Widget build(BuildContext context) {
    final booking = _bookingFrom(context.watch<AppState>().myBookings);
    if (booking == null) return const SizedBox.shrink();
    final text = theme.onSurface;
    final date = booking.requestedDate == null ? null : formatShortDate(booking.requestedDate!);

    final (String label, Color color, String message, List<Widget> actions) = switch (booking.status) {
      BookingStatus.pending when !booking.isShortlet => (
        'Not paid',
        const Color(0xFF8A6D1F),
        "Payment for this property wasn't completed. You can finish it from Booking History.",
        const <Widget>[],
      ),
      BookingStatus.pending => ('Pending', const Color(0xFF8A6D1F), 'Waiting for the landlord to accept your booking request.', const <Widget>[]),
      BookingStatus.accepted => (
        'Accepted',
        const Color(0xFF1F6FA8),
        'The landlord accepted your booking. Pay for it from Booking History to confirm your stay.',
        const <Widget>[],
      ),
      BookingStatus.paid => ('Booked', const Color(0xFF2F855A), 'Your stay is paid for and confirmed.', const <Widget>[]),
      BookingStatus.paidAwaitingInspection => (
        'Payment held',
        const Color(0xFF8A6D1F),
        'Your payment is held safely. Choose an inspection date whenever you are ready.',
        [if (widget.onBookInspection != null) _button('Book Inspection', widget.onBookInspection!)],
      ),
      BookingStatus.inspectionProposed => (
        'Pending',
        const Color(0xFF8A6D1F),
        date == null
            ? 'Waiting for the landlord to accept your inspection date.'
            : 'Waiting for the landlord to accept your inspection date ($date).',
        [if (widget.onBookInspection != null) _button('Change date', widget.onBookInspection!, outlined: true)],
      ),
      BookingStatus.inspectionConfirmed => (
        'Inspection confirmed',
        const Color(0xFF1F6FA8),
        '${date == null ? 'Your inspection is confirmed.' : 'Your inspection is confirmed for $date.'} '
            "Once you're ready to move in, confirm it here.",
        [_button('Moved In', () => _confirmMovedIn(booking))],
      ),
      BookingStatus.movedIn => (
        'Rented',
        const Color(0xFF2F855A),
        'You have successfully rented this property.',
        [_button('View Tenancy Agreement', () => _openAgreement(booking))],
      ),
      BookingStatus.declined => ('Declined', const Color(0xFFB42318), 'The landlord rejected this booking — you were refunded in full.', const <Widget>[]),
      BookingStatus.refunded => ('Refunded', const Color(0xFF5B6475), 'This booking was refunded.', const <Widget>[]),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: text.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Your booking', style: AppTextStyles.body(color: text, size: 14, weight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Text(label, style: AppTextStyles.body(color: color, size: 11.5, weight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (booking.status == BookingStatus.movedIn) ...[
                Icon(Icons.check_circle_rounded, color: color, size: 18),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  message,
                  style: AppTextStyles.body(
                    color: text.withValues(alpha: 0.85),
                    size: 13,
                    weight: booking.status == BookingStatus.movedIn ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_busy)
              Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: text)))
            else
              Wrap(spacing: 10, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }

  /// A filled theme.accent button with its onAccent label, or (outlined)
  /// an onSurface border and label — not accent, which is sand on Midnight
  /// and would vanish against the white surface.
  Widget _button(String label, VoidCallback onPressed, {bool outlined = false}) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(side: BorderSide(color: theme.onSurface, width: 1.2), padding: padding, shape: shape),
        child: Text(label, style: AppTextStyles.body(color: theme.onSurface, size: 13, weight: FontWeight.w700)),
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: theme.accent, padding: padding, shape: shape),
      child: Text(label, style: AppTextStyles.body(color: theme.onAccent, size: 13, weight: FontWeight.w700)),
    );
  }
}

/// "Lekki Phase 1, Lagos" — without repeating the state when the location
/// already ends with it.
String _placeLine(Property p) =>
    p.location.toLowerCase().trim().endsWith(p.state.toLowerCase().trim()) ? p.location : '${p.location}, ${p.state}';

/// The body of the property-details sheet: for a tenant, where their rental
/// stands; then the photos (tap for the full-screen gallery), address,
/// price, rooms and description. The sheet is theme.surface, so all text is
/// theme.onSurface (a fixed contrast pair in every DashboardTheme).
class _PropertyDetailsSheet extends StatelessWidget {
  const _PropertyDetailsSheet({required this.theme, required this.property, required this.showTenantStatus, this.onBookInspection});

  final DashboardTheme theme;
  final Property property;
  final bool showTenantStatus;

  /// Null hides the tenant panel's "Book inspection" step.
  final VoidCallback? onBookInspection;

  @override
  Widget build(BuildContext context) {
    final text = theme.onSurface;
    final images = [property.image, ...property.galleryImages].where((p) => p.isNotEmpty).toSet().toList();
    Widget fact(IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: text.withValues(alpha: 0.75), size: 17),
          const SizedBox(width: 5),
          Text(label, style: AppTextStyles.body(color: text, size: 13, weight: FontWeight.w600)),
        ],
      ),
    );
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text('Property details', style: AppTextStyles.heading(color: text, size: 17))),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: text),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                if (showTenantStatus) ...[
                  _TenantBookingStatusPanel(theme: theme, propertyId: property.id, onBookInspection: onBookInspection),
                  const SizedBox(height: 16),
                ],
                if (images.isNotEmpty)
                  SizedBox(
                    height: 210,
                    child: PageView(
                      children: [
                        for (var i = 0; i < images.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Semantics(
                              button: true,
                              label: 'View photo',
                              child: GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => PropertyGalleryScreen(images: images, initialIndex: i, title: property.title),
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: PropertyImage(path: images[i], width: double.infinity, height: 210),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (images.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Swipe for ${images.length - 1} more photo${images.length == 2 ? '' : 's'}',
                      style: AppTextStyles.body(color: text.withValues(alpha: 0.7), size: 12),
                    ),
                  ),
                const SizedBox(height: 14),
                Text(property.title, style: AppTextStyles.heading(color: text, size: 19)),
                const SizedBox(height: 4),
                Text(
                  [if (property.unitAddress?.isNotEmpty ?? false) property.unitAddress!, _placeLine(property)].join(' · '),
                  style: AppTextStyles.body(color: text.withValues(alpha: 0.8), size: 13.5),
                ),
                if (property.listingNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Listing #${property.listingNumber}', style: AppTextStyles.body(color: text.withValues(alpha: 0.7), size: 12.5)),
                  ),
                const SizedBox(height: 12),
                Text(property.priceLabel, style: AppTextStyles.heading(color: text, size: 17)),
                const SizedBox(height: 10),
                Wrap(
                  children: [
                    fact(Icons.home_work_outlined, property.category),
                    fact(Icons.bed_outlined, '${property.bedrooms} bed${property.bedrooms == 1 ? '' : 's'}'),
                    fact(Icons.bathtub_outlined, '${property.bathrooms} bath${property.bathrooms == 1 ? '' : 's'}'),
                  ],
                ),
                if (property.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('About this property', style: AppTextStyles.body(color: text, size: 14, weight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(property.description, style: AppTextStyles.body(color: text.withValues(alpha: 0.85), size: 13.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
