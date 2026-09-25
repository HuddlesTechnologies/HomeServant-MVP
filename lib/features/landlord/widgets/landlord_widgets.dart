import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Composite "house with a person" glyph used across the landlord redesign
/// (bottom nav's Bookings tab, the Bookings/Incoming Bookings section
/// headers) — there's no single Material icon for "booking request", so
/// this layers a small person badge on the bottom-right of a house icon.
class HouseBookingIcon extends StatelessWidget {
  const HouseBookingIcon({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.home_rounded, color: color, size: size),
          Positioned(
            right: -size * 0.18,
            bottom: -size * 0.12,
            child: Icon(Icons.person_rounded, color: color, size: size * 0.52),
          ),
        ],
      ),
    );
  }
}

/// The dark navy rounded bar used to label a section — e.g. "Bookings" /
/// "Rent" on the Bookings screen — carrying an icon plus a label.
class LandlordSectionPill extends StatelessWidget {
  const LandlordSectionPill({super.key, required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Text(label, style: AppTextStyles.body(color: AppColors.gold, size: 15, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// One of the four gold stat tiles on the landlord Home tab (Properties /
/// Occupied / Available / Booking Request).
class LandlordStatCard extends StatelessWidget {
  const LandlordStatCard({
    super.key,
    required this.icon,
    required this.iconBackground,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconBackground;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: iconBackground, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.white, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value, style: AppTextStyles.heading(color: AppColors.navy, size: 20)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: AppTextStyles.body(color: AppColors.navy, size: 11.5, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Plain circular avatar placeholder — every person in the new landlord
/// screens (bookings, messages) is mock data with no portrait asset, so
/// every list tile uses this instead of a photo.
class LandlordAvatar extends StatelessWidget {
  const LandlordAvatar({super.key, this.radius = 22, this.background, this.iconColor});

  final double radius;
  final Color? background;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: background ?? AppColors.hintGrey.withValues(alpha: 0.25),
      child: Icon(Icons.person_rounded, color: iconColor ?? AppColors.hintGrey, size: radius),
    );
  }
}

/// The green-check / red-cross accept-reject pair shown on every pending
/// booking row.
class LandlordAcceptRejectButtons extends StatelessWidget {
  const LandlordAcceptRejectButtons({
    super.key,
    required this.onAccept,
    required this.onReject,
    this.acceptTooltip,
    this.rejectTooltip,
  });

  final VoidCallback onAccept;
  final VoidCallback onReject;

  /// Optional tooltip text — used on the Bookings screen so the checkmark
  /// reads as "Confirm inspection date" rather than a generic accept for a
  /// non-Shortlet property.
  final String? acceptTooltip;
  final String? rejectTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleIconButton(icon: Icons.check_rounded, color: const Color(0xFF3FBF6A), onTap: onAccept, tooltip: acceptTooltip),
        const SizedBox(width: 8),
        _CircleIconButton(icon: Icons.close_rounded, color: const Color(0xFFE0554F), onTap: onReject, tooltip: rejectTooltip),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.color, required this.onTap, this.tooltip});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.4)),
        child: Icon(icon, color: color, size: 16),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
