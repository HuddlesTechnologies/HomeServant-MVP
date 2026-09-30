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

/// Every detail an admin can see about a listing, reached by tapping a
/// row in AdminPropertiesTab or a transaction's "View full property".
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

  /// Moderator+. Search ranking — Normal / Boosted / Top, for a number of
  /// days or until changed, with a reason for the activity log.
  Future<void> _setRanking(Property property) async {
    final result = await showModalBottomSheet<({int level, int? days, String reason})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _RankingSheet(property: property),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.setPropertyBoost(property.id, level: result.level, days: result.days, reason: result.reason);
      messenger.showSnackBar(SnackBar(content: Text('Search ranking updated for ${property.title}')));
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
                        LabeledValueRow('Kitchens', '${property.kitchens}'),
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
                  const SizedBox(height: 12),
                  _RankingCard(property: property, onChange: context.canModerate ? () => _setRanking(property) : null),
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

const _levelLabels = ['Normal', 'Boosted', 'Top'];

/// Where this listing stands in search: its admin ranking, any paid
/// "Featured" ad, and how many bookings it has had (to spot popular ones).
/// White card, navy text.
class _RankingCard extends StatelessWidget {
  const _RankingCard({required this.property, required this.onChange});

  final Property property;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final boost = property.adminBoostActive ? property.adminBoost : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Search ranking', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
              ),
              if (onChange != null)
                TextButton(
                  onPressed: onChange,
                  child: Text('Change', style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w700)),
                ),
            ],
          ),
          LabeledValueRow(
            'Admin ranking',
            boost == 0
                ? 'Normal'
                : '${_levelLabels[boost]}${property.adminBoostUntil != null ? ' until ${formatShortDate(property.adminBoostUntil!.toLocal())}' : ' (until changed)'}',
          ),
          LabeledValueRow(
            'Paid ad',
            property.featured
                ? 'Featured until ${property.featuredUntil != null ? formatShortDate(property.featuredUntil!.toLocal()) : '—'}'
                : 'None running',
          ),
          if (property.bookingsCount != null) LabeledValueRow('Bookings so far', '${property.bookingsCount}'),
          const SizedBox(height: 6),
          Text(
            'Ranked and featured listings share one promoted spot in every few results, and only while they can be '
            'booked — a booked-out shortlet shows after the available ones.',
            style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.7), size: 12),
          ),
        ],
      ),
    );
  }
}

/// Picks the ranking level, for how long, and why. White sheet, navy text;
/// the text field sets its own colours (see CLAUDE.md).
class _RankingSheet extends StatefulWidget {
  const _RankingSheet({required this.property});

  final Property property;

  @override
  State<_RankingSheet> createState() => _RankingSheetState();
}

class _RankingSheetState extends State<_RankingSheet> {
  late int _level = widget.property.adminBoostActive ? widget.property.adminBoost : 0;
  int? _days = 30;
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Search ranking', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
            const SizedBox(height: 4),
            Text(widget.property.title, style: AppTextStyles.body(color: AppColors.hintGrey, size: 13)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              children: [
                for (var level = 0; level < _levelLabels.length; level++)
                  ChoiceChip(
                    label: Text(
                      _levelLabels[level],
                      style: AppTextStyles.body(color: _level == level ? Colors.white : AppColors.navy, size: 13, weight: FontWeight.w700),
                    ),
                    selected: _level == level,
                    selectedColor: AppColors.navy,
                    backgroundColor: AppColors.offWhite,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _level = level),
                  ),
              ],
            ),
            if (_level > 0) ...[
              const SizedBox(height: 14),
              Text('For how long', style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final (days, label) in const [(7, '7 days'), (30, '30 days'), (90, '90 days'), (null, 'Until changed')])
                    ChoiceChip(
                      label: Text(
                        label,
                        style: AppTextStyles.body(color: _days == days ? Colors.white : AppColors.navy, size: 12.5, weight: FontWeight.w600),
                      ),
                      selected: _days == days,
                      selectedColor: AppColors.navy,
                      backgroundColor: AppColors.offWhite,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _days = days),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              style: AppTextStyles.body(color: AppColors.navy, size: 14),
              cursorColor: AppColors.navy,
              decoration: InputDecoration(
                labelText: 'Why (recorded in the activity log)',
                labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                hintText: 'e.g. popular shortlet with great reviews',
                hintStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final reason = _reason.text.trim();
                  if (reason.length < 5) {
                    setState(() => _error = 'Say briefly why');
                    return;
                  }
                  Navigator.of(context).pop((level: _level, days: _level > 0 ? _days : null, reason: reason));
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                ),
                child: Text('Save ranking', style: AppTextStyles.button(color: Colors.white, size: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
