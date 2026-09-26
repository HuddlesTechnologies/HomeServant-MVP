import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/booking.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/dashboard_page_scaffold.dart';
import '../dashboard/models/property.dart';
import '../dashboard/property_detail_screen.dart';
import '../dashboard/widgets/property_image.dart';
import 'landlord_add_property_screen.dart';
import 'landlord_property_status.dart';

/// The booking that put the current tenant into [property], if any — the
/// most recent MOVED_IN (non-Shortlet)/PAID (Shortlet) booking against it.
/// [landlordBookings] is ordered newest-first by the API, so the first
/// match is the current occupancy even if the property has changed hands
/// between tenants before.
Booking? _activeBookingFor(Property property, List<Booking> landlordBookings) {
  for (final booking in landlordBookings) {
    if (booking.property.id != property.id) continue;
    if (booking.status == BookingStatus.movedIn || booking.status == BookingStatus.paid) return booking;
  }
  return null;
}

enum PropertyStatusFilter { all, occupied, available }

/// The landlord's full property list — reached by tapping any of the
/// Properties/Occupied/Available stat tiles on the Home tab. Filters to a
/// status when opened from Occupied/Available; shows everything otherwise.
class LandlordPropertiesScreen extends StatelessWidget {
  const LandlordPropertiesScreen({super.key, required this.theme, this.filter = PropertyStatusFilter.all});

  final DashboardTheme theme;
  final PropertyStatusFilter filter;

  String get _title => switch (filter) {
    PropertyStatusFilter.all => 'My Properties',
    PropertyStatusFilter.occupied => 'Occupied Properties',
    PropertyStatusFilter.available => 'Available Properties',
  };

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final all = appState.landlordProperties;
    final landlordBookings = appState.landlordBookings;
    final entries = switch (filter) {
      PropertyStatusFilter.all => all,
      PropertyStatusFilter.occupied => all.where(isOccupied).toList(),
      PropertyStatusFilter.available => all.where(isAvailable).toList(),
    };

    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: _title,
      body: SafeArea(
        child: entries.isEmpty
            ? Center(
                child: Text(
                  'No properties here yet.',
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: entries.length,
                    itemBuilder: (context, index) => _PropertyTile(
                      property: entries[index],
                      occupied: isOccupied(entries[index]),
                      activeBooking: _activeBookingFor(entries[index], landlordBookings),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PropertyDetailScreen(property: entries[index], theme: theme),
                        ),
                      ),
                      onEdit: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => LandlordAddPropertyScreen(initial: entries[index]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _PropertyTile extends StatelessWidget {
  const _PropertyTile({
    required this.property,
    required this.occupied,
    required this.activeBooking,
    required this.onTap,
    required this.onEdit,
  });

  final Property property;
  final bool occupied;

  /// The current tenant's booking, when [occupied] — null for an available
  /// property, and also null for an occupied Shortlet (those never carry
  /// lease dates the same way, see [_activeBookingFor]'s doc comment).
  final Booking? activeBooking;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: PropertyImage(path: property.image, width: 72, height: 72),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.title,
                    style: AppTextStyles.body(color: AppColors.navy, size: 15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(property.location, style: AppTextStyles.body(color: AppColors.hintGrey, size: 13)),
                  if (property.listingNumber != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Listing #${property.listingNumber}',
                      style: AppTextStyles.body(color: AppColors.navy, size: 12, weight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (occupied ? const Color(0xFF3FBF6A) : AppColors.gold).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      occupied ? 'Occupied' : 'Available',
                      style: AppTextStyles.body(
                        color: occupied ? const Color(0xFF1E8A4A) : AppColors.goldDark,
                        size: 11,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (activeBooking != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Tenant: ${activeBooking!.tenantName ?? 'Unknown'}',
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: AppColors.navy, size: 12, weight: FontWeight.w600),
                    ),
                    if (activeBooking!.leaseEndDate != null)
                      Text(
                        'Rent expires ${formatShortDate(activeBooking!.leaseEndDate!)}',
                        style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                      ),
                    if (activeBooking!.lastPaidAt != null)
                      Text(
                        'Last paid ${formatShortDate(activeBooking!.lastPaidAt!)}',
                        style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                      ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, color: AppColors.navy),
              tooltip: 'Edit listing',
            ),
          ],
        ),
      ),
    );
  }
}
