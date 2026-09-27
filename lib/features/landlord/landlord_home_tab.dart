import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/booking.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/upload_picker.dart';
import '../dashboard/chat_thread_screen.dart';
import '../dashboard/models/property.dart';
import '../dashboard/notifications_screen.dart';
import '../dashboard/property_detail_screen.dart';
import '../dashboard/widgets/property_image.dart';
import 'landlord_add_property_screen.dart';
import 'landlord_properties_screen.dart';
import 'landlord_tenants_screen.dart';
import 'landlord_property_status.dart';
import '../profile/verification_submit_screen.dart';
import '../../api/models/verification.dart';
import 'widgets/landlord_widgets.dart';

/// Home tab of the redesigned landlord dashboard: greeting header, the four
/// portfolio stat tiles, a recent-activity card of incoming bookings, a
/// today's-overview summary, and a strip of recently uploaded property
/// photos. Every tile here is a real destination — tapping a stat opens the
/// filtered property list, a booking opens a chat with that tenant, and the
/// nav-switching arrows/avatar hand off to the dashboard shell's other tabs.
class LandlordHomeTab extends StatefulWidget {
  const LandlordHomeTab({super.key, required this.theme, required this.onOpenBookings, required this.onOpenProfile});

  final DashboardTheme theme;

  /// Switches the parent dashboard shell to the Bookings tab.
  final VoidCallback onOpenBookings;

  /// Switches the parent dashboard shell to the Profile Settings tab.
  final VoidCallback onOpenProfile;

  @override
  State<LandlordHomeTab> createState() => _LandlordHomeTabState();
}

class _LandlordHomeTabState extends State<LandlordHomeTab> {
  DashboardTheme get theme => widget.theme;

  void _openProperties(BuildContext context, PropertyStatusFilter filter) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LandlordPropertiesScreen(theme: theme, filter: filter)),
    );
  }

  Future<void> _messageAboutBooking(BuildContext context, Booking booking) async {
    final appState = context.read<AppState>();
    final tenantId = booking.tenantId;
    if (tenantId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final thread = await appState.chat.openThread(recipientId: tenantId, propertyId: booking.property.id);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            theme: theme,
            contactName: booking.tenantName ?? 'Tenant',
            threadId: thread.id,
            property: booking.property,
            otherParticipant: thread.otherParticipant,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't open this conversation — try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final photoPath = appState.profilePhotoPath;
    final firstName = appState.fullName.trim().isEmpty ? 'Landlord' : appState.fullName.trim();
    final allProperties = appState.landlordProperties;
    final occupied = allProperties.where(isOccupied).length;
    final available = allProperties.length - occupied;
    final pendingBookings = appState.landlordBookings.where((b) => b.status == BookingStatus.pending).toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onOpenProfile,
                  child: Container(
                    width: 44,
                    height: 44,
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
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${timeOfDayGreeting()}, $firstName',
                        style: AppTextStyles.heading(color: theme.foreground, size: 17),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Here's what's happening today",
                        style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 12.5),
                      ),
                    ],
                  ),
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
            const SizedBox(height: 20),
            if (context.watch<AppState>().listingsHiddenUntilVerified) ...[
              // White card, navy text + dark red warning: fixed pair in every theme.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.visibility_off_outlined, color: Color(0xFFA61B1B), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your listings are hidden from tenants',
                            style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'HomeServant only shows listings from verified landlords. Yours will appear as soon as your identity is verified.',
                            style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 12.5),
                          ),
                          if (canSubmitVerification(context.watch<AppState>().verificationStatus)) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 36,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.navy,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const VerificationSubmitScreen()),
                                ),
                                child: Text('Get verified', style: AppTextStyles.body(color: Colors.white, size: 13, weight: FontWeight.w700)),
                              ),
                            ),
                          ] else if (context.watch<AppState>().verificationStatus == VerificationStatus.pending) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Your documents are with us for review.',
                              style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openProperties(context, PropertyStatusFilter.all),
                    child: LandlordStatCard(
                      icon: Icons.apartment_rounded,
                      iconBackground: AppColors.navy,
                      value: '${allProperties.length}',
                      label: 'Properties',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openProperties(context, PropertyStatusFilter.occupied),
                    child: LandlordStatCard(
                      icon: Icons.meeting_room_rounded,
                      iconBackground: const Color(0xFF3FBF6A),
                      value: '$occupied',
                      label: 'Occupied',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _openProperties(context, PropertyStatusFilter.available),
                    child: LandlordStatCard(
                      icon: Icons.villa_rounded,
                      iconBackground: AppColors.hintGrey,
                      value: '$available',
                      label: 'Available',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: widget.onOpenBookings,
                    child: LandlordStatCard(
                      icon: Icons.people_alt_rounded,
                      iconBackground: const Color(0xFF3FBF6A),
                      // Used to be a hardcoded '5+', so the card showed
                      // requests the Bookings tab (correctly) didn't have.
                      // Same pending set that tab's "Upcoming Bookings" and
                      // "Incoming Bookings" below list.
                      value: '${pendingBookings.length}',
                      label: pendingBookings.length == 1 ? 'Booking Request' : 'Booking Requests',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.accent,
                      foregroundColor: theme.onAccent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LandlordAddPropertyScreen()),
                    ),
                    icon: Icon(Icons.add_home_work_rounded, color: theme.onAccent, size: 20),
                    label: Text('Upload a Property', style: AppTextStyles.button(color: theme.onAccent, size: 14.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  // Outlined on theme.background, so text is theme.foreground.
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.foreground.withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LandlordTenantsScreen()),
                    ),
                    icon: Icon(Icons.groups_rounded, color: theme.foreground, size: 20),
                    label: Text('My Tenants', style: AppTextStyles.button(color: theme.foreground, size: 14.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            InkWell(
              onTap: widget.onOpenBookings,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Activity', style: AppTextStyles.heading(color: theme.foreground, size: 17)),
                  Icon(Icons.arrow_forward_rounded, color: theme.foreground),
                ],
              ),
            ),
            const SizedBox(height: 12),
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
                          HouseBookingIcon(color: AppColors.gold, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'Incoming Bookings',
                            style: AppTextStyles.body(color: AppColors.gold, size: 15, weight: FontWeight.w700),
                          ),
                        ],
                      ),
                      if (pendingBookings.isNotEmpty)
                        InkWell(
                          onTap: widget.onOpenBookings,
                          child: Text(
                            'See all',
                            style: AppTextStyles.body(
                              color: Colors.white.withValues(alpha: 0.6),
                              size: 12.5,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (pendingBookings.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No incoming bookings right now.',
                        style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 13),
                      ),
                    )
                  else
                    for (final booking in pendingBookings.take(5))
                      _IncomingBookingTile(booking: booking, onTap: () => _messageAboutBooking(context, booking)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onOpenBookings,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Today Overview',
                          style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w700),
                        ),
                        const Icon(Icons.arrow_forward_rounded, color: AppColors.navy, size: 18),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.bed_rounded, color: AppColors.navy, size: 26),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              allProperties.isEmpty ? '—' : '${(occupied / allProperties.length * 100).round()}%',
                              style: const TextStyle(color: Color(0xFF1E8A4A), fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'Occupancy Rate',
                              style: AppTextStyles.body(color: AppColors.navy, size: 11.5, weight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(width: 28),
                        const Icon(Icons.groups_rounded, color: AppColors.navy, size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${appState.landlordBookings.length}',
                                style: AppTextStyles.heading(color: AppColors.navy, size: 18),
                              ),
                              Text(
                                'Total Requests',
                                style: AppTextStyles.body(color: AppColors.navy, size: 11.5, weight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(child: Text('Uploads', style: AppTextStyles.heading(color: theme.foreground, size: 17))),
                if (allProperties.isNotEmpty)
                  TextButton(
                    onPressed: () => _openProperties(context, PropertyStatusFilter.all),
                    child: Text(
                      'See all',
                      style: AppTextStyles.body(color: theme.foreground, size: 13.5, weight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: allProperties.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) => InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PropertyDetailScreen(property: allProperties[index], theme: theme, ownerView: true),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _UploadThumbnail(property: allProperties[index]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A listing's photo with its key details over a dark scrim — title,
/// price and whether it's occupied — so the landlord can tell listings
/// apart without opening each one. White text on a near-black scrim is a
/// fixed pair regardless of the photo underneath.
class _UploadThumbnail extends StatelessWidget {
  const _UploadThumbnail({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      height: 140,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PropertyImage(path: property.image, width: 180, height: 140),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              color: Colors.black.withValues(alpha: 0.62),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    property.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(color: Colors.white, size: 12.5, weight: FontWeight.w700),
                  ),
                  Text(
                    '${property.priceLabel} · ${isOccupied(property) ? 'Occupied' : 'Available'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(color: Colors.white, size: 11),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomingBookingTile extends StatelessWidget {
  const _IncomingBookingTile({required this.booking, required this.onTap});

  final Booking booking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
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
                    style: AppTextStyles.body(color: Colors.white, size: 14, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${booking.property.title} • ${formatShortDate(booking.createdAt)}',
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.6), size: 11.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.notifications_none_rounded, color: AppColors.gold.withValues(alpha: 0.85), size: 20),
          ],
        ),
      ),
    );
  }
}
