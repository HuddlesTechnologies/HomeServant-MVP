import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/models/booking.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import '../../widgets/eviction_widgets.dart';
import '../../widgets/upload_picker.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/labeled_value_row.dart';
import '../../widgets/profile_photo_viewer.dart';

/// Read-only tenant profile — reached from a landlord's booking row via
/// "View Tenant Profile". Shows only what `GET /bookings/landlord` already
/// hands back for that tenant (see [Booking]'s `tenant*` fields) — a
/// landlord never gets an arbitrary lookup, only the tenant behind one of
/// their own bookings. Any field that's null (a tenant hasn't filled in
/// occupation, say) is simply omitted rather than shown as "—"/"null",
/// matching admin's user-detail screen and the tenant's own profile screen
/// for visual consistency (photo circle + a plain white "field list" card).
class TenantProfileViewScreen extends StatelessWidget {
  const TenantProfileViewScreen({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    // Every booking this tenant has with this landlord, newest first; the
    // tenancies section below lists the ones where they paid or moved in.
    final all = [
      for (final b in appState.landlordBookings)
        if (b.tenantId != null && b.tenantId == booking.tenantId) b,
    ];
    if (all.isEmpty) all.add(booking);
    final tenancies = [for (final b in all) if (b.status == BookingStatus.movedIn || b.status == BookingStatus.paid) b];
    final phone = all.map((b) => b.tenantPhone).firstWhere((p) => p != null && p.isNotEmpty, orElse: () => null);
    final photoUrl = booking.tenantProfilePhotoUrl;
    final age = booking.tenantAge;
    final occupation = booking.tenantOccupation;
    final hasAnyDetail =
        age != null || booking.tenantGender != null || (occupation != null && occupation.isNotEmpty) || booking.tenantMaritalStatus != null;

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Tenant Profile', style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Center(
              child: ProfilePhotoTapTarget(
                photoPath: photoUrl,
                name: booking.tenantName,
                child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.hintGrey.withValues(alpha: 0.2),
                  border: Border.all(color: AppColors.navy, width: 1.4),
                  image: photoUrl != null && photoUrl.isNotEmpty
                      ? DecorationImage(image: imageProviderForPath(photoUrl), fit: BoxFit.cover)
                      : null,
                ),
                child: (photoUrl == null || photoUrl.isEmpty)
                    ? const Icon(Icons.person_rounded, color: AppColors.navy, size: 44)
                    : null,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                booking.tenantName?.isNotEmpty == true ? booking.tenantName! : 'Tenant',
                style: AppTextStyles.heading(color: AppColors.navy, size: 20),
              ),
            ),
            if (all.any((b) => b.tenantVerified)) ...[
              const SizedBox(height: 6),
              const Center(child: VerifiedBadge(textColor: AppColors.navy, label: 'Verified tenant')),
            ],
            if (booking.tenantEmail != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  booking.tenantEmail!,
                  style: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('Email', booking.tenantEmail ?? 'Not available'),
                  _field('Phone', phone ?? 'Shared once they pay for your property'),
                  if (age != null) _field('Age', '$age'),
                  if (booking.tenantGender != null) _field('Gender', booking.tenantGender!.label),
                  _field('Occupation', occupation != null && occupation.isNotEmpty ? occupation : 'Not provided'),
                  _field('Marital Status', booking.tenantMaritalStatus?.label ?? 'Not provided'),
                  if (!hasAnyDetail)
                    Text(
                      "This tenant hasn't filled in the rest of their profile yet.",
                      style: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                    ),
                ],
              ),
            ),
            // Their booking profile: what they wrote about themselves and
            // their hobbies. White card, navy text; hobby chips are navy on
            // a pale navy wash.
            if (booking.tenantBio?.trim().isNotEmpty == true || booking.tenantHobbies.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (booking.tenantBio?.trim().isNotEmpty == true) ...[
                      Text('About', style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(booking.tenantBio!.trim(), style: AppTextStyles.body(color: AppColors.navy, size: 13.5)),
                    ],
                    if (booking.tenantHobbies.isNotEmpty) ...[
                      if (booking.tenantBio?.trim().isNotEmpty == true) const SizedBox(height: 14),
                      Text('Hobbies', style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final hobby in booking.tenantHobbies)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.navy.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(hobby, style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (tenancies.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Tenancies with you', style: AppTextStyles.heading(color: AppColors.navy, size: 17)),
              const SizedBox(height: 10),
              for (final t in tenancies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  // Off-white page, so navy text; the eviction sheet itself
                  // uses the dashboard theme's surface/onSurface pair.
                  child: LandlordTenancyCard(
                    booking: t,
                    theme: appState.dashboardTheme,
                    textColor: AppColors.navy,
                    caption: t.isShortlet ? 'Shortlet stay' : 'Rental',
                    title: t.property.title,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

LabeledValueRow _field(String label, String value) =>
    LabeledValueRow(label, value, labelWidth: 120);
