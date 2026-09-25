import 'package:flutter/material.dart';
import '../../api/models/booking.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/upload_picker.dart';

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
            const SizedBox(height: 14),
            Center(
              child: Text(
                booking.tenantName?.isNotEmpty == true ? booking.tenantName! : 'Tenant',
                style: AppTextStyles.heading(color: AppColors.navy, size: 20),
              ),
            ),
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
                  if (age != null) _Field('Age', '$age'),
                  if (booking.tenantGender != null) _Field('Gender', booking.tenantGender!.label),
                  if (occupation != null && occupation.isNotEmpty) _Field('Occupation', occupation),
                  if (booking.tenantMaritalStatus != null) _Field('Marital Status', booking.tenantMaritalStatus!.label),
                  if (!hasAnyDetail)
                    Text(
                      "This tenant hasn't filled in these profile details yet.",
                      style: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
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

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))),
          Expanded(child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600))),
        ],
      ),
    );
  }
}
