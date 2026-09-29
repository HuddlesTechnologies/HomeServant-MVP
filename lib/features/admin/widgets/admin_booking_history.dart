import 'package:flutter/material.dart';
import '../../../api/models/admin_models.dart';
import '../../../core/date_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/thousands_separator.dart';
import '../../../widgets/upload_picker.dart';
import '../../dashboard/property_gallery_screen.dart';
import 'admin_badge.dart';

// A tenant's booking history in the admin console. White card, navy text
// (AppColors), tone colours drawn as dark text on a pale wash of the same
// colour (AdminBadge) — every text colour below is explicit (see CLAUDE.md).

/// How many bookings always stay on show; older ones fold away.
const _alwaysShown = 3;

Color historyToneColor(HistoryTone tone) => switch (tone) {
  HistoryTone.success => const Color(0xFF067647),
  HistoryTone.pending => const Color(0xFFB54708),
  HistoryTone.warning => const Color(0xFF9A3412),
  HistoryTone.danger => const Color(0xFFB42318),
  HistoryTone.info => AppColors.navy,
};

String _stamp(DateTime at) {
  final t = at.toLocal();
  return '${formatShortDate(t)}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _words(String raw) =>
    raw.toLowerCase().split('_').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

String _naira(int amount) => '₦${formatWithThousandsSeparator(amount)}';

/// The newest [_alwaysShown] bookings (newest at the top — the API sends
/// them newest first) plus a Show all / Show fewer toggle for the rest.
/// Each booking opens up to its full property details, images, payments
/// and a dated timeline.
class AdminBookingHistoryCard extends StatefulWidget {
  const AdminBookingHistoryCard({super.key, required this.bookings});

  final List<AdminUserBooking> bookings;

  @override
  State<AdminBookingHistoryCard> createState() => _AdminBookingHistoryCardState();
}

class _AdminBookingHistoryCardState extends State<AdminBookingHistoryCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final bookings = [...widget.bookings]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final hidden = bookings.length - _alwaysShown;
    final visible = _showAll ? bookings : bookings.take(_alwaysShown).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Booking History (${bookings.length})',
                  style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14),
                ),
              ),
              if (hidden > 0)
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(
                    _showAll ? 'Show latest $_alwaysShown only' : 'Show all ${bookings.length}',
                    style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          Text(
            'Newest first. Tap a booking for the property, images, payments and every step with its date and time.',
            style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
          ),
          const SizedBox(height: 8),
          for (final booking in visible) _BookingTile(key: ValueKey(booking.id), booking: booking),
          if (hidden > 0)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(() => _showAll = !_showAll),
                icon: Icon(_showAll ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.navy),
                label: Text(
                  _showAll ? 'Hide older bookings' : 'Show $hidden older booking${hidden == 1 ? '' : 's'}',
                  style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BookingTile extends StatefulWidget {
  const _BookingTile({super.key, required this.booking});

  final AdminUserBooking booking;

  @override
  State<_BookingTile> createState() => _BookingTileState();
}

class _BookingTileState extends State<_BookingTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final property = booking.property;
    final thumb = property != null && property.images.isNotEmpty ? property.images.first : null;
    final outcomeColor = historyToneColor(booking.outcomeTone);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: thumb != null
                        ? Image(image: imageProviderForPath(thumb), width: 56, height: 56, fit: BoxFit.cover)
                        : Container(
                            width: 56,
                            height: 56,
                            color: Colors.white,
                            child: const Icon(Icons.home_outlined, color: AppColors.hintGrey, size: 22),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.propertyTitle,
                          style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 13.5),
                        ),
                        if (property != null)
                          Text(
                            'Listing #${property.listingNumber} · ${property.location}, ${property.state}',
                            style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                          ),
                        Text(
                          'Booked ${_stamp(booking.createdAt)}',
                          style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                        ),
                        const SizedBox(height: 4),
                        AdminBadge(
                          text: booking.outcome ?? _words(booking.status),
                          color: outcomeColor,
                          size: AdminBadgeSize.small,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_naira(booking.price)}/${booking.priceUnit.toLowerCase()}',
                        style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 13),
                      ),
                      Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: AppColors.navy),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_open) _BookingDetails(booking: booking),
        ],
      ),
    );
  }
}

class _BookingDetails extends StatelessWidget {
  const _BookingDetails({required this.booking});

  final AdminUserBooking booking;

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12))),
        Expanded(child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w600))),
      ],
    ),
  );

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 6),
    child: Text(text, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w800)),
  );

  @override
  Widget build(BuildContext context) {
    final property = booking.property;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (property != null && property.images.isNotEmpty)
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: property.images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PropertyGalleryScreen(images: property.images, initialIndex: index, title: property.title),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(image: imageProviderForPath(property.images[index]), width: 112, height: 84, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          if (property != null) ...[
            _heading('Property'),
            _row('Category', _words(property.category)),
            _row('Rooms', '${property.bedrooms} bed · ${property.bathrooms} bath'),
            _row('Listed price', '${_naira(property.price)}/${property.priceUnit.toLowerCase()}'),
            if (property.rentDurationMonths != null) _row('Lease length', '${property.rentDurationMonths} months'),
            _row('Address', '${property.location}, ${property.state}'),
            if (property.unitAddress?.isNotEmpty == true || property.roomNumber?.isNotEmpty == true)
              _row('Unit', [property.unitAddress, property.roomNumber].where((p) => p?.isNotEmpty == true).join(' · ')),
            _row('Right now', property.isOccupied ? 'Occupied' : 'Vacant'),
            _row(
              'Landlord',
              [property.landlordName, property.landlordEmail, property.landlordPhone].where((p) => p?.isNotEmpty == true).join(' · '),
            ),
            if (property.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(property.description, style: AppTextStyles.body(color: AppColors.navy, size: 12.5)),
            ],
          ],
          _heading('This booking'),
          _row('Status', booking.outcome ?? _words(booking.status)),
          _row('Price charged', '${_naira(booking.price)}/${booking.priceUnit.toLowerCase()}'),
          if (booking.payingMonthly)
            _row(
              'Payment plan',
              'Monthly${booking.monthlyRent != null ? ' · ${_naira(booking.monthlyRent!)}/month' : ''}'
                  '${booking.rentPaidThrough != null ? ' · paid until ${formatShortDate(booking.rentPaidThrough!.toLocal())}' : ''}',
            ),
          if (booking.requestedDate != null)
            _row(booking.nights != null ? 'Check-in' : 'Inspection date', _stamp(booking.requestedDate!)),
          if (booking.nights != null) _row('Nights', '${booking.nights}'),
          if (booking.leaseStartDate != null) _row(booking.nights != null ? 'Stay' : 'Lease', _leaseRange(booking)),
          if (booking.payments.isNotEmpty) ...[
            _heading('Payments'),
            for (final payment in booking.payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_naira(payment.amount ~/ 100)} · ${_words(payment.status)}',
                            style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w700),
                          ),
                          Text(
                            'Ref ${payment.reference} · started ${_stamp(payment.createdAt)}',
                            style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          _heading('Timeline'),
          if (booking.timeline.isEmpty)
            Text('No events recorded.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12))
          else
            for (var i = 0; i < booking.timeline.length; i++)
              _TimelineRow(event: booking.timeline[i], isLast: i == booking.timeline.length - 1),
        ],
      ),
    );
  }

  static String _leaseRange(AdminUserBooking booking) {
    final start = formatShortDate(booking.leaseStartDate!.toLocal());
    final end = booking.leaseEndDate != null ? formatShortDate(booking.leaseEndDate!.toLocal()) : '…';
    return '$start – $end';
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.isLast});

  final BookingTimelineEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = historyToneColor(event.tone);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                if (!isLast) Expanded(child: Container(width: 2, color: AppColors.navy.withValues(alpha: 0.12))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.label, style: AppTextStyles.body(color: color, size: 12.5, weight: FontWeight.w700)),
                  Text(_stamp(event.at), style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5)),
                  if (event.detail?.isNotEmpty == true)
                    Text(event.detail!, style: AppTextStyles.body(color: AppColors.navy, size: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
