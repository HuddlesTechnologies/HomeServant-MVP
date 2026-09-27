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

enum _PropertySort { newest, oldest, priceHigh, priceLow, name, rentExpiring }

extension on _PropertySort {
  String get label => switch (this) {
    _PropertySort.newest => 'Newest first',
    _PropertySort.oldest => 'Oldest first',
    _PropertySort.priceHigh => 'Price: high to low',
    _PropertySort.priceLow => 'Price: low to high',
    _PropertySort.name => 'Name (A–Z)',
    _PropertySort.rentExpiring => 'Rent expiring soonest',
  };
}

const _categories = ['All', 'House', 'Shortlet', 'Self-Con', 'Apartment'];

/// The landlord's full property list — reached by tapping any of the
/// Properties/Occupied/Available stat tiles (or "See all") on the Home tab.
/// Searchable by title, location or listing number, filterable by status
/// and category, and sortable; each card carries the key details (price,
/// rooms, status, pending requests, current tenant and rent expiry) so the
/// landlord doesn't have to open every listing to see them.
class LandlordPropertiesScreen extends StatefulWidget {
  const LandlordPropertiesScreen({super.key, required this.theme, this.filter = PropertyStatusFilter.all});

  final DashboardTheme theme;
  final PropertyStatusFilter filter;

  @override
  State<LandlordPropertiesScreen> createState() => _LandlordPropertiesScreenState();
}

class _LandlordPropertiesScreenState extends State<LandlordPropertiesScreen> {
  late PropertyStatusFilter _status = widget.filter;
  String _category = _categories.first;
  _PropertySort _sort = _PropertySort.newest;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesStatus(Property p) => switch (_status) {
    PropertyStatusFilter.all => true,
    PropertyStatusFilter.occupied => isOccupied(p),
    PropertyStatusFilter.available => isAvailable(p),
  };

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final appState = context.watch<AppState>();
    final all = appState.landlordProperties;
    final landlordBookings = appState.landlordBookings;
    final query = _search.text.trim().toLowerCase();

    // The API returns listings newest-first, so list order is the "newest"
    // order (the client has no createdAt of its own).
    final entries = [
      for (final p in all)
        if (_matchesStatus(p) &&
            (_category == 'All' || p.category == _category) &&
            (query.isEmpty ||
                p.title.toLowerCase().contains(query) ||
                p.location.toLowerCase().contains(query) ||
                '${p.listingNumber ?? ''}'.contains(query.replaceAll('#', ''))))
          p,
    ];
    final activeBookings = {for (final p in entries) p.id: _activeBookingFor(p, landlordBookings)};
    switch (_sort) {
      case _PropertySort.newest:
        break;
      case _PropertySort.oldest:
        entries.setAll(0, entries.reversed.toList());
      case _PropertySort.priceHigh:
        entries.sort((a, b) => b.price.compareTo(a.price));
      case _PropertySort.priceLow:
        entries.sort((a, b) => a.price.compareTo(b.price));
      case _PropertySort.name:
        entries.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _PropertySort.rentExpiring:
        DateTime? end(Property p) => activeBookings[p.id]?.leaseEndDate;
        entries.sort((a, b) {
          final ea = end(a), eb = end(b);
          if (ea == null && eb == null) return 0;
          if (ea == null) return 1;
          if (eb == null) return -1;
          return ea.compareTo(eb);
        });
    }
    final pendingByProperty = <String, int>{};
    for (final b in landlordBookings) {
      if (b.status == BookingStatus.pending) {
        pendingByProperty[b.property.id] = (pendingByProperty[b.property.id] ?? 0) + 1;
      }
    }
    final occupiedCount = all.where(isOccupied).length;

    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: 'My Properties',
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  // theme.surface/onSurface: a fixed light-fill/navy-text pair.
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    style: AppTextStyles.body(color: theme.onSurface, size: 14),
                    cursorColor: theme.onSurface,
                    decoration: InputDecoration(
                      hintText: 'Search by name, location or listing #',
                      hintStyle: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.5), size: 14),
                      prefixIcon: Icon(Icons.search_rounded, color: theme.onSurface.withValues(alpha: 0.5)),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: Icon(Icons.close_rounded, color: theme.onSurface.withValues(alpha: 0.6)),
                              onPressed: () => setState(_search.clear),
                            ),
                      filled: true,
                      fillColor: theme.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _ChipRow(
                  theme: theme,
                  labels: [
                    'All (${all.length})',
                    'Occupied ($occupiedCount)',
                    'Available (${all.length - occupiedCount})',
                  ],
                  selected: PropertyStatusFilter.values.indexOf(_status),
                  onSelect: (i) => setState(() => _status = PropertyStatusFilter.values[i]),
                ),
                const SizedBox(height: 8),
                _ChipRow(
                  theme: theme,
                  labels: _categories,
                  selected: _categories.indexOf(_category),
                  onSelect: (i) => setState(() => _category = _categories[i]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${entries.length} ${entries.length == 1 ? 'property' : 'properties'}',
                          style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.7), size: 13),
                        ),
                      ),
                      PopupMenuButton<_PropertySort>(
                        tooltip: 'Sort',
                        color: Colors.white,
                        initialValue: _sort,
                        onSelected: (value) => setState(() => _sort = value),
                        itemBuilder: (_) => [
                          for (final option in _PropertySort.values)
                            PopupMenuItem(
                              value: option,
                              child: Text(
                                option.label,
                                style: AppTextStyles.body(
                                  color: AppColors.navy,
                                  size: 14,
                                  weight: option == _sort ? FontWeight.w700 : FontWeight.w400,
                                ),
                              ),
                            ),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sort_rounded, color: theme.foreground, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _sort.label,
                                style: AppTextStyles.body(color: theme.foreground, size: 13, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(
                            all.isEmpty ? 'No properties here yet.' : 'No properties match these filters.',
                            style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
                            final property = entries[index];
                            return _PropertyTile(
                              property: property,
                              occupied: isOccupied(property),
                              activeBooking: activeBookings[property.id],
                              pendingRequests: pendingByProperty[property.id] ?? 0,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PropertyDetailScreen(property: property, theme: theme, ownerView: true),
                                ),
                              ),
                              onEdit: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => LandlordAddPropertyScreen(initial: property)),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontally scrolling row of filter pills — accent/onAccent when
/// selected, surface/onSurface otherwise (both fixed contrast pairs).
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.theme, required this.labels, required this.selected, required this.onSelect});

  final DashboardTheme theme;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isSelected = index == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelect(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? theme.accent : theme.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                labels[index],
                style: AppTextStyles.body(
                  color: isSelected ? theme.onAccent : theme.onSurface,
                  size: 13,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PropertyTile extends StatelessWidget {
  const _PropertyTile({
    required this.property,
    required this.occupied,
    required this.activeBooking,
    required this.pendingRequests,
    required this.onTap,
    required this.onEdit,
  });

  /// Booking requests on this listing still waiting on the landlord.
  final int pendingRequests;

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
              child: PropertyImage(path: property.image, width: 96, height: 96),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(color: AppColors.navy, size: 15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    property.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${property.priceLabel} · ${property.category} · '
                    '${property.bedrooms} bed · ${property.bathrooms} bath',
                    style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w600),
                  ),
                  if (property.listingNumber != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Listing #${property.listingNumber}',
                      style: AppTextStyles.body(color: AppColors.navy, size: 12, weight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // Dark text on a light tint of its own hue, over the
                      // white card (gold-dark text on pale gold was too faint).
                      _Pill(
                        label: occupied ? 'Occupied' : 'Available',
                        background: (occupied ? const Color(0xFF3FBF6A) : AppColors.gold).withValues(alpha: 0.25),
                        foreground: occupied ? const Color(0xFF1E6B3A) : AppColors.landlordBrown,
                      ),
                      if (pendingRequests > 0)
                        _Pill(
                          label: '$pendingRequests pending ${pendingRequests == 1 ? 'request' : 'requests'}',
                          background: AppColors.navy,
                          foreground: Colors.white,
                        ),
                      if (!property.messagingEnabled)
                        _Pill(
                          label: 'Messaging off',
                          background: AppColors.navy.withValues(alpha: 0.08),
                          foreground: AppColors.navy,
                        ),
                    ],
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

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: AppTextStyles.body(color: foreground, size: 11, weight: FontWeight.w700)),
    );
  }
}
