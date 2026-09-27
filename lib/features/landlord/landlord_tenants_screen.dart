import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/booking.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/verified_badge.dart';
import 'tenant_profile_view_screen.dart';

enum _TenantFilter { current, former, all }

/// One person who has rented from this landlord, with every tenancy they
/// had (newest first) — a tenant renting two units shows once.
class _TenantEntry {
  _TenantEntry(this.tenantId, this.tenancies);

  final String tenantId;
  final List<Booking> tenancies;

  Booking get latest => tenancies.first;
  String get name => latest.tenantName?.trim().isNotEmpty == true ? latest.tenantName!.trim() : 'Tenant';

  static bool isCurrent(Booking b) =>
      (b.status == BookingStatus.movedIn || b.status == BookingStatus.paid) &&
      (b.leaseEndDate == null || b.leaseEndDate!.isAfter(DateTime.now()));

  /// The tenancy to summarise in the list: a current one if any.
  Booking get headline => tenancies.firstWhere(isCurrent, orElse: () => latest);
  bool get current => tenancies.any(isCurrent);
}

/// Landlord: everyone who has rented (moved in) or booked a paid shortlet
/// stay at one of their properties. Search by name; tap for the tenant's
/// profile, their tenancies and the eviction option.
class LandlordTenantsScreen extends StatefulWidget {
  const LandlordTenantsScreen({super.key});

  @override
  State<LandlordTenantsScreen> createState() => _LandlordTenantsScreenState();
}

class _LandlordTenantsScreenState extends State<LandlordTenantsScreen> {
  final _search = TextEditingController();
  String _query = '';
  _TenantFilter _filter = _TenantFilter.current;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    appState.loadLandlordBookings().catchError((_) {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<_TenantEntry> _entries(List<Booking> bookings) {
    final byTenant = <String, List<Booking>>{};
    for (final b in bookings) {
      final id = b.tenantId;
      if (id == null) continue;
      if (b.status != BookingStatus.movedIn && b.status != BookingStatus.paid) continue;
      byTenant.putIfAbsent(id, () => []).add(b);
    }
    DateTime started(Booking b) => b.leaseStartDate ?? b.createdAt;
    final entries = [
      for (final e in byTenant.entries) _TenantEntry(e.key, e.value..sort((a, b) => started(b).compareTo(started(a)))),
    ];
    final q = _query.trim().toLowerCase();
    final filtered = entries.where((e) {
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      return switch (_filter) {
        _TenantFilter.current => e.current,
        _TenantFilter.former => !e.current,
        _TenantFilter.all => true,
      };
    }).toList();
    // Current tenants: soonest expiry first. Others: alphabetical.
    filtered.sort((a, b) {
      if (a.current && b.current) {
        final ae = a.headline.leaseEndDate, be = b.headline.leaseEndDate;
        if (ae != null && be != null) return ae.compareTo(be);
      }
      if (a.current != b.current) return a.current ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = appState.dashboardTheme;
    final entries = _entries(appState.landlordBookings);
    final evictionsPending = {
      for (final e in appState.evictions)
        if (e.isPending) e.bookingId,
    };

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text('My Tenants', style: AppTextStyles.heading(color: theme.foreground, size: 20)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: RefreshIndicator(
              onRefresh: () => appState.loadLandlordBookings(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  // White search pill, navy text — the same pair as the
                  // tenant dashboard search, fixed in every theme.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: AppColors.navy),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            onChanged: (v) => setState(() => _query = v),
                            style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Search tenants by name',
                              hintStyle: AppTextStyles.body(color: AppColors.hintGrey),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            child: const Icon(Icons.close_rounded, color: AppColors.hintGrey, size: 20),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in _TenantFilter.values)
                        ChoiceChip(
                          label: Text(switch (f) {
                            _TenantFilter.current => 'Current',
                            _TenantFilter.former => 'Former',
                            _TenantFilter.all => 'All',
                          }),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                          showCheckmark: false,
                          selectedColor: theme.accent,
                          backgroundColor: Colors.white,
                          side: _filter == f ? BorderSide.none : BorderSide(color: AppColors.navy.withValues(alpha: 0.15)),
                          labelStyle: AppTextStyles.body(
                            color: _filter == f ? theme.onAccent : AppColors.navy,
                            size: 13,
                            weight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Text(
                        _query.isNotEmpty
                            ? 'No tenants match "$_query".'
                            : _filter == _TenantFilter.former
                            ? 'No former tenants yet.'
                            : 'No tenants yet. They appear here once they move in.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                      ),
                    )
                  else
                    for (final e in entries)
                      _TenantTile(
                        entry: e,
                        theme: theme,
                        evictionPending: e.tenancies.any((b) => evictionsPending.contains(b.id)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => TenantProfileViewScreen(booking: e.headline)),
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
}

/// White card with navy text, in every theme.
class _TenantTile extends StatelessWidget {
  const _TenantTile({required this.entry, required this.theme, required this.evictionPending, required this.onTap});

  final _TenantEntry entry;
  final DashboardTheme theme;
  final bool evictionPending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = entry.headline;
    final start = b.leaseStartDate;
    final end = b.leaseEndDate;
    final current = _TenantEntry.isCurrent(b);
    final others = entry.tenancies.length - 1;
    final expiringSoon = current && end != null && end.difference(DateTime.now()).inDays <= 30;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.navy,
                  child: Text(
                    entry.name.characters.first.toUpperCase(),
                    style: AppTextStyles.body(color: Colors.white, size: 16, weight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.name,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body(color: AppColors.navy, size: 15, weight: FontWeight.w700),
                            ),
                          ),
                          if (entry.tenancies.any((t) => t.tenantVerified)) ...[
                            const SizedBox(width: 4),
                            const VerifiedBadge(textColor: AppColors.navy, label: null, size: 12),
                          ],
                          const Spacer(),
                          _Tag(
                            label: evictionPending ? 'Eviction under review' : (current ? 'Current' : 'Former'),
                            color: evictionPending
                                ? const Color(0xFFB7791F)
                                : current
                                ? const Color(0xFF2F855A)
                                : AppColors.hintGrey,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        others > 0 ? '${b.property.title} (+$others more)' : b.property.title,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5),
                      ),
                      const SizedBox(height: 8),
                      _dateRow('Rented on', start == null ? 'Not started yet' : formatShortDate(start)),
                      _dateRow(
                        current ? 'Rent expires' : 'Rent ended',
                        end == null ? '—' : formatShortDate(end),
                        highlight: expiringSoon,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AppColors.hintGrey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateRow(String label, String value, {bool highlight = false}) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        SizedBox(width: 92, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))),
        Text(
          highlight ? '$value (soon)' : value,
          style: AppTextStyles.body(
            color: highlight ? const Color(0xFFC53030) : AppColors.navy,
            size: 12.5,
            weight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

/// Tinted pill; the label stays navy for contrast whatever the tint.
class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: AppTextStyles.body(color: AppColors.navy, size: 11, weight: FontWeight.w700)),
    );
  }
}
