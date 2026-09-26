import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import '../dashboard/models/property.dart';
import '../dashboard/widgets/property_image.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_permissions.dart';

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
                            if (property.isOccupied) const _Badge(text: 'Occupied', color: Colors.orange),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _Field('Location', property.location),
                        _Field('State', property.state),
                        _Field('Category', property.category),
                        _Field('Price', '₦${formatWithThousandsSeparator(property.price)}/${property.priceUnit}'),
                        _Field('Bedrooms', '${property.bedrooms}'),
                        _Field('Bathrooms', '${property.bathrooms}'),
                        if (property.rentDurationMonths != null)
                          _Field('Lease Duration', '${property.rentDurationMonths} months'),
                        if (property.unitAddress != null && property.unitAddress!.isNotEmpty)
                          _Field('Unit Address', property.unitAddress!),
                        if (property.roomNumber != null && property.roomNumber!.isNotEmpty)
                          _Field('Room Number', property.roomNumber!),
                        _Field('Messaging Enabled', property.messagingEnabled ? 'Yes' : 'No'),
                        _Field('Landlord', property.landlordName),
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
                        label: const Text('Re-list (override occupied lock)', style: TextStyle(color: Colors.orange)),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _remove(property),
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                      label: const Text('Remove Listing', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
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
          SizedBox(
            width: 140,
            child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: AppTextStyles.body(color: color, size: 10.5, weight: FontWeight.w700)),
    );
  }
}
