import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';

/// "This listing has been hidden because the landlord is unverified" —
/// shown to a tenant who booked or saved a listing that Platform Controls
/// now hides from browsing. White card with navy text and an amber icon,
/// so it reads on every theme's background.
class HiddenListingNotice extends StatelessWidget {
  const HiddenListingNotice({
    super.key,
    this.hasBooking = false,
    this.isShortlet = false,
    this.ownerView = false,
    this.byLandlord = false,
  });

  /// The landlord hid it themselves (not Platform Controls).
  final bool byLandlord;

  /// The tenant has a booking here: reassure them it carries on.
  final bool hasBooking;
  final bool isShortlet;

  /// The landlord looking at their own hidden listing.
  final bool ownerView;

  @override
  Widget build(BuildContext context) {
    final who = isShortlet ? 'owner' : 'landlord';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFB7791F).withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.visibility_off_outlined, color: Color(0xFFB7791F), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ownerView
                      ? 'This listing is hidden from tenants'
                      : byLandlord
                      ? 'The $who has hidden this listing for now'
                      : 'This listing has been hidden because the $who is unverified',
                  style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  byLandlord
                      ? ownerView
                            ? "You hid it: tenants can't find or book it. Show it again from My Properties any time."
                            : hasBooking
                            ? 'Other tenants can no longer find it. Your booking is not affected.'
                            : "It doesn't show up in search and can't be booked until the $who shows it again."
                      : ownerView
                      ? 'HomeServant only shows listings from verified landlords. It will show again as soon as your identity is verified; your current tenants and bookings are not affected.'
                      : hasBooking
                      ? 'Other tenants can no longer find it. Your booking is not affected: you can still continue, move in, message the $who or ask for a refund as usual.'
                      : "It no longer shows up in search and can't be booked until the $who is verified by HomeServant.",
                  style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact version over a listing photo (saved listings): solid white pill.
class HiddenListingPill extends StatelessWidget {
  const HiddenListingPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.visibility_off_outlined, color: Color(0xFFB7791F), size: 14),
          const SizedBox(width: 4),
          Text('Hidden: landlord unverified', style: AppTextStyles.body(color: AppColors.navy, size: 11, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}
