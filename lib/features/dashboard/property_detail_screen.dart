import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/open_payment_page.dart';
import '../../api/api_exception.dart';
import '../../api/models/booking.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/eviction_widgets.dart';
import '../landlord/landlord_add_property_screen.dart';
import 'chat_thread_screen.dart';
import 'edit_profile_screen.dart';
import 'history_screen.dart';
import 'models/property.dart';
import 'property_gallery_screen.dart';
import 'widgets/property_image.dart';
import 'widgets/property_video_player.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/hidden_listing_notice.dart';
import '../../widgets/report_sheet.dart';
import 'widgets/shortlet_unavailable_countdown.dart';

/// Every [BookingStatus] from the moment a tenant's payment clears onward.
/// A tenant sees a property's listing number only once they've paid;
/// landlords and admins always see it.
const _paidBookingStatuses = {
  BookingStatus.paid,
  BookingStatus.paidAwaitingInspection,
  BookingStatus.inspectionProposed,
  BookingStatus.inspectionConfirmed,
  BookingStatus.movedIn,
};

/// Why this tenant can't Rent Now / Book Now again, or null if they can.
/// A rental that's paid for (or lived in, until the lease ends) blocks
/// renting it again; a Shortlet only blocks a second request while one is
/// still waiting on the landlord or on payment — booking another stay
/// after that is fine.
String? _existingBookingNote(Iterable<Booking> bookings, bool isShortlet) {
  final now = DateTime.now();
  for (final b in bookings) {
    if (isShortlet) {
      if (b.status == BookingStatus.pending) return 'Your booking request is waiting on the landlord.';
      if (b.status == BookingStatus.accepted) return 'Your booking was accepted — pay for it from Booking History.';
      continue;
    }
    if (b.status == BookingStatus.movedIn && (b.leaseEndDate == null || b.leaseEndDate!.isAfter(now))) {
      return "You're renting this property.";
    }
    if (_paidBookingStatuses.contains(b.status) && b.status != BookingStatus.movedIn) {
      return "You've paid for this property. Book your inspection or manage it from Booking History.";
    }
  }
  return null;
}

class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({super.key, required this.property, required this.theme, this.ownerView = false});

  final Property property;
  final DashboardTheme theme;

  /// Set by the landlord's own screens (Properties list, dashboard
  /// uploads). The screen also detects ownership itself from
  /// [Property.landlordId], so either is enough to swap the tenant-facing
  /// Rent Now / Message Landlord / favorite actions for Edit Property.
  final bool ownerView;

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  bool _descriptionExpanded = false;
  bool _bookingBusy = false;

  // Starts as whatever the caller passed in (usually from an already-
  // stale list) and is swapped for a fresh copy once [_refreshProperty]
  // resolves — see initState. Kept as a plain field (not widget.property)
  // so a price/availability change made elsewhere while this screen is
  // already open shows up without needing to leave and reopen it.
  late Property _property = widget.property;

  @override
  void initState() {
    super.initState();
    _refreshProperty();
  }

  Future<void> _refreshProperty() async {
    try {
      final fresh = await context.read<AppState>().fetchProperty(widget.property.id);
      if (mounted) setState(() => _property = fresh);
    } catch (_) {
      // Leaves the passed-in snapshot in place — better than blocking the
      // screen (or showing an error) over a background refresh that
      // failed while the caller's own data was already good enough to
      // render from.
    }
  }

  List<String> get _allPhotos => [_property.image, ..._property.galleryImages];

  void _openGallery(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyGalleryScreen(images: _allPhotos, initialIndex: index, title: _property.title),
      ),
    );
  }

  /// For a Shortlet, the number of nights is required by `POST /bookings` —
  /// prompted with a small stepper dialog before the request is sent.
  /// Pay the year in full, or monthly (first month now). Null = cancelled.
  /// theme.surface/onSurface is a fixed light-surface/navy-text pair.
  Future<bool?> _pickPaymentPlan(Property property) {
    final theme = widget.theme;
    Widget option({required String title, required String subtitle, required bool monthly}) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: AppTextStyles.body(color: theme.onSurface, size: 15, weight: FontWeight.w700)),
      subtitle: Text(subtitle, style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.7), size: 12.5)),
      trailing: Icon(Icons.chevron_right_rounded, color: theme.onSurface.withValues(alpha: 0.6)),
      onTap: () => Navigator.of(context).pop(monthly),
    );
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: theme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How would you like to pay?', style: AppTextStyles.heading(color: theme.onSurface, size: 18)),
              const SizedBox(height: 8),
              option(
                title: 'Pay in full · ₦${formatNaira(property.price)}',
                subtitle: 'The whole year now, held safely until you move in.',
                monthly: false,
              ),
              option(
                title: 'Pay monthly · ₦${formatNaira(property.monthlyPrice)}/month',
                subtitle: "The first month now, held until you move in; then each month as it's due. We'll remind you.",
                monthly: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _pickNights() async {
    var nights = 1;
    return showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => AlertDialog(
          title: const Text('How many nights?'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Fewer nights',
                onPressed: nights > 1 ? () => setSheetState(() => nights--) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Text('$nights', style: AppTextStyles.heading(color: widget.theme.foreground, size: 22)),
              IconButton(
                tooltip: 'More nights',
                onPressed: () => setSheetState(() => nights++),
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(context).pop(nights), child: const Text('Confirm')),
          ],
        ),
      ),
    );
  }

  Future<void> _messageLandlord() async {
    final property = _property;
    final landlordId = property.landlordId;
    if (landlordId == null) return;
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final thread = await appState.chat.openThread(recipientId: landlordId, propertyId: property.id);
      if (!mounted) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            theme: widget.theme,
            contactName: thread.otherParticipantName,
            property: property,
            threadId: thread.id,
            otherParticipant: thread.otherParticipant,
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  bool _deleting = false;

  /// Owner-only. Asks for confirmation, then deletes; the server decides
  /// whether that's allowed (not while occupied or with a tenant's payment
  /// held) and its reason is shown if not.
  Future<void> _deleteProperty() async {
    final property = _property;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete this listing?', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
        content: Text(
          '"${property.title}" will be removed for good, including its photos and booking history. '
          'This can\'t be undone.',
          style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600)),
          ),
          TextButton(
            style: TextButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _deleting = true);
    try {
      await context.read<AppState>().deleteLandlordProperty(property.id);
      messenger.showSnackBar(SnackBar(content: Text('"${property.title}" was deleted')));
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _editProperty() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LandlordAddPropertyScreen(initial: _property)),
    );
    if (mounted) _refreshProperty();
  }

  @override
  Widget build(BuildContext context) {
    final property = _property;
    final theme = widget.theme;
    final userId = context.select<AppState, String?>((state) => state.userId);
    final isOwner = widget.ownerView || (property.landlordId != null && property.landlordId == userId);
    final favorited = context.select<AppState, bool>((state) => state.isFavorite(property.id));
    final hasPaidForProperty = context.select<AppState, bool>(
      (state) => state.myBookings.any((b) => b.property.id == property.id && _paidBookingStatuses.contains(b.status)),
    );
    final messagingEnabled = property.messagingEnabled;
    final isShortlet = property.category == 'Shortlet';
    final unavailable = isShortlet && property.shortletUnavailable;
    // Once a tenant has an active booking here, Rent Now is replaced by a
    // note pointing at it, so they can't pay for the same property twice
    // (the server refuses a second booking too).
    final existingBookingNote = context.select<AppState, String?>(
      (state) => _existingBookingNote(state.myBookings.where((b) => b.property.id == property.id), isShortlet),
    );
    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(
                    property: property,
                    favorited: favorited,
                    showFavorite: !isOwner,
                    onToggleFavorite: () => context.read<AppState>().toggleFavorite(property.id),
                    onBack: () => Navigator.of(context).pop(),
                    onOpenGallery: () => _openGallery(0),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -28),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.background,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _FeatureIcon(
                                theme: theme,
                                icon: Icons.bed_outlined,
                                label: '${property.bedrooms} Bedroom${property.bedrooms == 1 ? '' : 's'}',
                              ),
                              _FeatureIcon(
                                theme: theme,
                                icon: Icons.bathtub_outlined,
                                label: '${property.bathrooms} Bathroom${property.bathrooms == 1 ? '' : 's'}',
                              ),
                              _FeatureIcon(
                                theme: theme,
                                icon: Icons.kitchen_outlined,
                                label: '${property.kitchens} Kitchen${property.kitchens == 1 ? '' : 's'}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 26),
                          if (property.hiddenUntilLandlordVerified || property.hiddenByLandlord) ...[
                            HiddenListingNotice(
                              ownerView: isOwner,
                              byLandlord: property.hiddenByLandlord && !property.hiddenUntilLandlordVerified,
                              isShortlet: property.category == 'Shortlet',
                              hasBooking: context.watch<AppState>().myBookings.any(
                                (b) =>
                                    b.property.id == property.id &&
                                    b.status != BookingStatus.declined &&
                                    b.status != BookingStatus.refunded,
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      property.title,
                                      style: AppTextStyles.heading(color: theme.foreground, size: 20),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      property.location,
                                      style: AppTextStyles.body(color: theme.accent, size: 14, weight: FontWeight.w700),
                                    ),
                                    if (property.landlordVerified) ...[
                                      const SizedBox(height: 6),
                                      // On theme.background, so the label uses theme.foreground.
                                      VerifiedBadge(
                                        textColor: theme.foreground,
                                        label: property.category == 'Shortlet' ? 'Verified owner' : 'Verified landlord',
                                      ),
                                    ],
                                    if (hasPaidForProperty && property.listingNumber != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Listing #${property.listingNumber}',
                                        style: AppTextStyles.body(
                                          color: theme.foreground.withValues(alpha: 0.65),
                                          size: 12.5,
                                          weight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    children: [
                                      ..._stars(property.rating, theme),
                                      const SizedBox(width: 4),
                                      Text(
                                        property.rating.toString(),
                                        style: AppTextStyles.body(color: theme.foreground, size: 13),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    property.priceLabel,
                                    style: AppTextStyles.body(color: theme.foreground, size: 16, weight: FontWeight.w700),
                                  ),
                                  if (property.allowMonthlyPayment && property.category != 'Shortlet')
                                    Text(
                                      'or ₦${formatNaira(property.monthlyPrice)}/month',
                                      style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.75), size: 12.5, weight: FontWeight.w600),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text('Description', style: AppTextStyles.heading(color: theme.foreground, size: 16)),
                          const SizedBox(height: 8),
                          _ExpandableDescription(
                            theme: theme,
                            text: property.description,
                            expanded: _descriptionExpanded,
                            onToggle: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                          ),
                          if (property.galleryImages.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Details Preview',
                              style: AppTextStyles.body(
                                color: theme.foreground.withValues(alpha: 0.55),
                                size: 13,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (var i = 0; i < property.galleryImages.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Semantics(button: true, label: 'View photo', child: GestureDetector(
                                      // Gallery index 0 is the hero photo, so the
                                      // preview strip's photos start at index 1.
                                      onTap: () => _openGallery(i + 1),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: PropertyImage(path: property.galleryImages[i], width: 72, height: 72),
                                      ),
                                    )),
                                  ),
                              ],
                            ),
                          ],
                          if (property.videoPath != null) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Property Tour',
                              style: AppTextStyles.body(
                                color: theme.foreground.withValues(alpha: 0.55),
                                size: 13,
                                weight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            PropertyVideoPlayer(path: property.videoPath!),
                          ],
                          const SizedBox(height: 24),
                          if (isOwner)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.accent,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                onPressed: _editProperty,
                                icon: Icon(Icons.edit_rounded, color: theme.onAccent, size: 18),
                                label: Text('Edit Property', style: AppTextStyles.button(color: theme.onAccent)),
                              ),
                            ),
                          if (isOwner) ...[
                            const SizedBox(height: 12),
                            // Text is theme.foreground (drawn on theme.background);
                            // the red is only the border/icon, a warning cue.
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  side: const BorderSide(color: Color(0xFFD64545), width: 1.4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                onPressed: _deleting ? null : _deleteProperty,
                                icon: _deleting
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: theme.foreground),
                                      )
                                    : const Icon(Icons.delete_outline_rounded, color: Color(0xFFD64545), size: 18),
                                label: Text(
                                  'Delete Listing',
                                  style: AppTextStyles.button(color: theme.foreground, size: 15),
                                ),
                              ),
                            ),
                            if (property.isOccupied) ...[
                              const SizedBox(height: 8),
                              Text(
                                'This property is occupied, so it can\'t be deleted until the tenancy ends.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 12.5),
                              ),
                            ],
                            LandlordEvictionPanel(property: property, theme: theme),
                          ] else ...[
                          if (unavailable)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.foreground.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: ShortletUnavailableCountdown(
                                until: property.shortletUnavailableUntil ?? DateTime.now(),
                                color: theme.foreground,
                              ),
                            )
                          else if (existingBookingNote != null)
                            _ExistingBookingNotice(
                              theme: theme,
                              message: existingBookingNote,
                              onViewHistory: () => Navigator.of(
                                context,
                              ).push(MaterialPageRoute(builder: (_) => HistoryScreen(theme: theme))),
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.accent,
                                  // Disabled (busy, or hidden by the landlord) keeps the accent so
                                  // the onAccent label still contrasts — not Material's grey.
                                  disabledBackgroundColor: theme.accent,
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                // A listing its landlord has hidden can't be
                                // booked (the server refuses too).
                                onPressed: _bookingBusy || property.hiddenByLandlord
                                    ? null
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        final appState = context.read<AppState>();
                                        int? nights;
                                        if (isShortlet) {
                                          nights = await _pickNights();
                                          if (nights == null || !mounted) return;
                                        }
                                        // The landlord allows monthly: pay in
                                        // full, or the first month now.
                                        var payMonthly = false;
                                        if (!isShortlet && property.allowMonthlyPayment) {
                                          final choice = await _pickPaymentPlan(property);
                                          if (choice == null || !mounted) return;
                                          payMonthly = choice;
                                        }
                                        setState(() => _bookingBusy = true);
                                        try {
                                          final result = await appState.recordRentalOrBooking(
                                            property.id,
                                            isShortlet: isShortlet,
                                            nights: nights,
                                            payMonthly: payMonthly,
                                          );
                                          if (!mounted) return;
                                          final payment = result.payment;
                                          if (payment != null) {
                                            // Non-Shortlet: the booking is charged as
                                            // soon as it's created (no landlord
                                            // approval first), so open the Paystack
                                            // checkout right away.
                                            final launched = await openPaymentPage(payment.authorizationUrl);
                                            if (!launched && mounted) {
                                              messenger.showSnackBar(
                                                const SnackBar(content: Text("Couldn't open the payment page — try again from Booking History.")),
                                              );
                                            }
                                          } else {
                                            messenger.showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '${isShortlet ? 'Booking' : 'Rent'} request sent for ${property.title}',
                                                ),
                                              ),
                                            );
                                          }
                                        } on ApiException catch (e) {
                                          messenger.showSnackBar(SnackBar(content: Text(e.message)));
                                        } finally {
                                          if (mounted) setState(() => _bookingBusy = false);
                                        }
                                      },
                                child: _bookingBusy
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2.4, color: theme.onAccent),
                                      )
                                    : Text(
                                        property.hiddenByLandlord
                                            ? 'Not available right now'
                                            : isShortlet
                                            ? 'Book Now'
                                            : 'Rent Now',
                                        style: AppTextStyles.button(color: theme.onAccent),
                                      ),
                              ),
                            ),
                          // Tenants who haven't told landlords anything about
                          // themselves yet: a nudge to fill in their booking
                          // profile (theme.foreground on theme.background).
                          if (!property.hiddenByLandlord &&
                              (context.watch<AppState>().bio?.trim().isEmpty ?? true) &&
                              context.watch<AppState>().hobbies.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: InkWell(
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen())),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_pin_outlined, color: theme.foreground, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Tip: add a little about yourself and your hobbies so the landlord gets to know you. Edit profile',
                                          style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.85), size: 12.5)
                                              .copyWith(decoration: TextDecoration.underline, decorationColor: theme.foreground),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          // Tenants can only message a landlord once they've
                          // paid — the backend enforces the same rule
                          // (ChatService.assertTenantMayMessageLandlord).
                          if (messagingEnabled && hasPaidForProperty)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  side: BorderSide(color: theme.accent, width: 1.4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                                ),
                                onPressed: _messageLandlord,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.chat_bubble_outline_rounded, color: theme.accent, size: 18),
                                    const SizedBox(width: 10),
                                    Text(
                                      property.category == 'Shortlet' ? 'Message Owner' : 'Message Landlord',
                                      style: AppTextStyles.button(color: theme.accent, size: 15),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (messagingEnabled)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'You can message the ${isShortlet ? 'owner' : 'landlord'} once you have paid for this property.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 12.5),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                'This landlord accepts direct rent payments only — messaging is turned off.',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.5), size: 12.5),
                              ),
                            ),
                          // Something wrong with the listing (a scam, misleading
                          // photos, a request to pay off-platform) goes to
                          // HomeServant's team. theme.foreground on background.
                          const SizedBox(height: 8),
                          Center(
                            child: TextButton.icon(
                              onPressed: () => showReportSheet(
                                context,
                                theme: theme,
                                target: ReportTarget.property,
                                targetId: property.id,
                                targetName: property.title,
                              ),
                              icon: Icon(Icons.flag_outlined, color: theme.foreground.withValues(alpha: 0.8), size: 18),
                              label: Text(
                                'Report this listing',
                                style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.8), size: 13, weight: FontWeight.w600),
                              ),
                            ),
                          ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Stars sit directly on `theme.background`, same as PropertyCard — using
  // theme.accent instead of a fixed gold avoids the gold-on-sand contrast
  // problem on the Sand theme.
  List<Widget> _stars(double rating, DashboardTheme theme) {
    final fullStars = rating.floor();
    final hasHalf = rating - fullStars >= 0.5;
    return List.generate(5, (index) {
      if (index < fullStars) return Icon(Icons.star_rounded, color: theme.accent, size: 16);
      if (index == fullStars && hasHalf) return Icon(Icons.star_half_rounded, color: theme.accent, size: 16);
      return Icon(Icons.star_rounded, color: theme.accent.withValues(alpha: 0.3), size: 16);
    });
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.property,
    required this.favorited,
    required this.showFavorite,
    required this.onToggleFavorite,
    required this.onBack,
    required this.onOpenGallery,
  });

  final Property property;
  final bool favorited;
  final bool showFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onBack;
  final VoidCallback onOpenGallery;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3 / 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(button: true, label: 'View photos', child: GestureDetector(onTap: onOpenGallery, child: PropertyImage(path: property.image))),
          Positioned(top: 16, left: 16, child: _CircleButton(icon: Icons.arrow_back_ios_new_rounded, label: 'Back', onTap: onBack)),
          if (showFavorite)
            Positioned(
              top: 16,
              right: 16,
              child: _CircleButton(
                icon: favorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                label: favorited ? 'Remove from wishlist' : 'Save to wishlist',
                iconColor: favorited ? Colors.redAccent : Colors.white,
                onTap: onToggleFavorite,
              ),
            ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.label, required this.onTap, this.iconColor = Colors.white});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: Colors.black.withValues(alpha: 0.35),
            child: Icon(icon, color: iconColor, size: 18),
          ),
        ),
      ),
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  const _FeatureIcon({required this.theme, required this.icon, required this.label});

  final DashboardTheme theme;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: theme.accent, size: 26),
        const SizedBox(height: 6),
        Text(label, style: AppTextStyles.body(color: theme.foreground, size: 12, weight: FontWeight.w600)),
      ],
    );
  }
}

class _ExpandableDescription extends StatelessWidget {
  const _ExpandableDescription({required this.theme, required this.text, required this.expanded, required this.onToggle});

  final DashboardTheme theme;
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          maxLines: expanded ? null : 3,
          overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.7), size: 14).copyWith(height: 1.5),
        ),
        GestureDetector(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              expanded ? 'Read less' : 'Read more',
              style: AppTextStyles.body(color: theme.accent, size: 14, weight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

/// Stands in for Rent Now once the tenant already has this property
/// booked. theme.foreground text on a faint foreground wash over
/// theme.background (a guaranteed pair); the button's accent label on
/// that same wash matches Booking History's action buttons.
class _ExistingBookingNotice extends StatelessWidget {
  const _ExistingBookingNotice({required this.theme, required this.message, required this.onViewHistory});

  final DashboardTheme theme;
  final String message;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(color: theme.foreground.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: theme.foreground, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: AppTextStyles.body(color: theme.foreground, size: 13.5, weight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: theme.accent, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              onPressed: onViewHistory,
              child: Text('View Booking History', style: AppTextStyles.body(color: theme.accent, size: 14, weight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
