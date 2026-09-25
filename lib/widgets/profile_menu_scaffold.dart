import 'package:flutter/material.dart';
import 'profile_edit_button.dart';
import 'profile_menu_tile.dart';
import 'upload_picker.dart';

/// Spec for one row in a [ProfileMenuScaffold]'s menu list — mirrors
/// [ProfileMenuTile]'s per-row parameters that vary between rows
/// (icon/label/onTap/showDivider), while the colour parameters are shared
/// across every row and live on [ProfileMenuScaffold] itself.
class ProfileMenuItemSpec {
  const ProfileMenuItemSpec({required this.icon, required this.label, required this.onTap, this.showDivider = true});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// False only for the last item in the list, matching every existing
  /// profile screen's menu (no trailing divider after "Log Out").
  final bool showDivider;
}

/// Shared shell for a profile screen's photo + edit button + menu list —
/// the tenant and landlord profile screens each used to define this same
/// layout by hand, differing only in their colour values (tenant: the
/// switchable `DashboardTheme`; landlord: fixed navy/gold) and their menu
/// items. Built from the existing [ProfileEditButton]/[ProfileMenuTile].
class ProfileMenuScaffold extends StatelessWidget {
  const ProfileMenuScaffold({
    super.key,
    required this.backgroundColor,
    required this.iconColor,
    required this.labelColor,
    required this.badgeColor,
    required this.dividerColor,
    required this.photoPath,
    required this.photoBorderColor,
    required this.editButtonColor,
    required this.onEditProfileTap,
    required this.items,
    this.header,
    this.footer,
  });

  /// Fills the whole screen behind the scrollable content — landlord wraps
  /// its own [Container] with this colour since its tab content sits inside
  /// a shared dashboard shell rather than its own [Scaffold]; tenant simply
  /// passes its theme's background the same way.
  final Color backgroundColor;

  /// Colour of every menu row's icon (`ProfileMenuTile.iconColor`).
  final Color iconColor;

  /// Colour of every menu row's label (`ProfileMenuTile.labelColor`).
  final Color labelColor;

  /// Fill colour of the circle behind every menu row's icon
  /// (`ProfileMenuTile.badgeColor`).
  final Color badgeColor;

  /// Colour of the divider under the photo and under every row that wants
  /// one (`ProfileMenuTile.dividerColor`).
  final Color dividerColor;

  final String? photoPath;
  final Color photoBorderColor;
  final Color editButtonColor;

  /// Both existing profile screens push the same `EditProfileScreen` here —
  /// taken as a callback (rather than this widget importing that screen
  /// itself) to keep this shared shell decoupled from a specific route.
  final VoidCallback onEditProfileTap;

  /// Optional content shown above the photo — landlord's profile tab has a
  /// "Profile Settings" heading row here that the tenant one doesn't.
  final Widget? header;

  final List<ProfileMenuItemSpec> items;

  /// Optional content shown below the menu list, outside its item rows —
  /// for a device-local toggle (e.g. the banner auto-dismiss switch) that
  /// isn't a navigable row itself, so doesn't fit [ProfileMenuItemSpec]'s
  /// icon+label+onTap shape.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
        children: [
          if (header != null) ...[header!, const SizedBox(height: 22)] else const SizedBox(height: 20),
          Container(
            width: 78,
            height: 78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: photoBorderColor, width: 1.4),
              // BoxFit.contain rather than cover — there's no crop step at
              // pick time, so covering the circle would zoom into whatever
              // was centered in the original photo instead of showing all
              // of it.
              image: photoPath != null
                  ? DecorationImage(image: imageProviderForPath(photoPath!), fit: BoxFit.contain)
                  : null,
            ),
            child: photoPath == null ? Icon(Icons.person_outline, color: photoBorderColor, size: 40) : null,
          ),
          const SizedBox(height: 16),
          ProfileEditButton(
            color: editButtonColor,
            onTap: onEditProfileTap,
          ),
          const SizedBox(height: 20),
          Divider(color: dividerColor, height: 1),
          for (final item in items)
            ProfileMenuTile(
              icon: item.icon,
              label: item.label,
              iconColor: iconColor,
              badgeColor: badgeColor,
              labelColor: labelColor,
              dividerColor: dividerColor,
              onTap: item.onTap,
              showDivider: item.showDivider,
            ),
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }
}
