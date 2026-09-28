import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../core/date_format.dart';
import '../../state/app_state.dart';
import '../dashboard/models/property.dart';
import '../dashboard/widgets/property_image.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_permissions.dart';
import '../../widgets/labeled_value_row.dart';
import 'widgets/admin_badge.dart';
import 'admin_user_detail_screen.dart';

/// Every detail an admin can see about a listing — reached by tapping a
/// row in AdminPropertiesTab, which previously had no detail view at all.
class AdminPropertyDetailScreen extends StatefulWidget {
  const AdminPropertyDetailScreen({super.key, required this.propertyId});

  final String propertyId;

  @override
  State<AdminPropertyDetailScreen> createState() => _AdminPropertyDetailScreenState();
}

class _AdminPropertyDetailScreenState extends State<AdminPropertyDetailScreen> {
  Property? _property;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final property = await context.read<AppState>().admin.propertyDetail(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _property = property;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load this property.");
    }
  }

  /// The landlord's full profile in a pop-up, with every action the
  /// admin's level allows. Afterwards the listing is re-read, since those
  /// actions can change it: deactivating hides it, and deleting the
  /// landlord (or this listing, from their list) deletes it, which closes
  /// this page.
  Future<void> _viewLandlord(String landlordId) async {
    await showAdminUserProfilePopup(context, userId: landlordId, title: 'Landlord Profile');
    if (!mounted) return;
    try {
      final property = await context.read<AppState>().admin.propertyDetail(widget.propertyId);
      if (mounted) setState(() => _property = property);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This listing no longer exists.')));
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _relist(Property property) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: 'Re-list "${property.title}"?',
      body:
          "This property is currently occupied and locked from re-listing by its landlord. This override makes "
          "it listable again — only do this if you've confirmed with the landlord that it's actually available.",
      actionLabel: 'Re-list',
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.relistProperty(property.id);
      messenger.showSnackBar(SnackBar(content: Text('${property.title} re-listed')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(Property property) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Remove "${property.title}"?',
      body: "This can't be undone — the listing and any bookings/reviews on it will be permanently deleted. The landlord is emailed the reason you give below.",
      actionLabel: 'Remove',
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<AppState>().admin.removeProperty(property.id, reason: reason);
      messenger.showSnackBar(SnackBar(content: Text('${property.title} removed')));
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final property = _property;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Property Details', style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: property == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (property.image.isNotEmpty || property.galleryImages.isNotEmpty)
                    SizedBox(
                      height: 160,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final path in [property.image, ...property.galleryImages])
                            if (path.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: PropertyImage(path: path, width: 220, height: 160),
                                ),
                              ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(property.title, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
                            ),
                            if (property.isOccupied) const AdminBadge(text: 'Occupied', color: Colors.orange),
                            if (property.hiddenByLandlord) ...[
                              const SizedBox(width: 6),
                              const AdminBadge(text: 'Hidden by landlord', color: AppColors.navy),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        LabeledValueRow('Listing #', property.listingNumber?.toString() ?? '—'),
                        if (property.imageChangesAllowed != null)
                          LabeledValueRow(
                            'Photo changes',
                            property.imagesLocked
                                ? 'Locked until ${formatShortDate(property.imagesLockedUntil!.toLocal())}'
                                : '${property.imageChangesLeft} of ${property.imageChangesAllowed} left',
                          ),
                        LabeledValueRow('Location', property.location),
                        LabeledValueRow('State', property.state),
                        LabeledValueRow('Category', property.category),
                        LabeledValueRow('Price', '₦${formatWithThousandsSeparator(property.price)}/${property.priceUnit}'),
                        LabeledValueRow('Bedrooms', '${property.bedrooms}'),
                        LabeledValueRow('Bathrooms', '${property.bathrooms}'),
                        if (property.rentDurationMonths != null)
                          LabeledValueRow('Lease Duration', '${property.rentDurationMonths} months'),
                        if (property.unitAddress != null && property.unitAddress!.isNotEmpty)
                          LabeledValueRow('Unit Address', property.unitAddress!),
                        if (property.roomNumber != null && property.roomNumber!.isNotEmpty)
                          LabeledValueRow('Room Number', property.roomNumber!),
                        LabeledValueRow('Messaging Enabled', property.messagingEnabled ? 'Yes' : 'No'),
                        _landlordRow(property),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Description', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                        const SizedBox(height: 8),
                        Text(
                          property.description.isEmpty ? 'No description provided.' : property.description,
                          style: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                        ),
                      ],
                    ),
                  ),
                  if (context.canModerate) ...[
                    const SizedBox(height: 20),
                    if (property.isOccupied)
                      OutlinedButton.icon(
                        onPressed: () => _relist(property),
                        icon: const Icon(Icons.lock_open_rounded, color: Colors.orange),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: Colors.orange),
                        ),
                        label: Text('Re-list (override occupied lock)', style: AppTextStyles.body(color: Colors.orange.shade800, size: 14, weight: FontWeight.w600)),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _remove(property),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      label: Text('Remove Listing', style: AppTextStyles.body(color: const Color(0xFFB42318), size: 14, weight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  /// Same layout as [LabeledValueRow], plus a "View profile" button.
  Widget _landlordRow(Property property) {
    final landlordId = property.landlordId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 140, child: Text('Landlord', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))),
          Expanded(
            child: Text(property.landlordName, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600)),
          ),
          if (landlordId != null)
            TextButton.icon(
              onPressed: () => _viewLandlord(landlordId),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.navy,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.navy),
              label: Text('View profile', style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
