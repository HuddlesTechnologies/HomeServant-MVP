import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../dashboard/models/property.dart';
import '../dashboard/property_detail_screen.dart';
import '../dashboard/widgets/property_image.dart';
import 'landlord_property_status.dart';

enum PropertyStatusFilter { all, occupied, available }

/// The landlord's full property list — reached by tapping any of the
/// Properties/Occupied/Available stat tiles on the Home tab. Filters to a
/// status when opened from Occupied/Available; shows everything otherwise.
class LandlordPropertiesScreen extends StatelessWidget {
  const LandlordPropertiesScreen({super.key, required this.theme, this.filter = PropertyStatusFilter.all});

  final DashboardTheme theme;
  final PropertyStatusFilter filter;

  String get _title => switch (filter) {
    PropertyStatusFilter.all => 'My Properties',
    PropertyStatusFilter.occupied => 'Occupied Properties',
    PropertyStatusFilter.available => 'Available Properties',
  };

  @override
  Widget build(BuildContext context) {
    final landlordAdded = context.watch<AppState>().landlordProperties;
    final all = [...mockProperties, ...landlordAdded];
    final entries = switch (filter) {
      PropertyStatusFilter.all => all,
      PropertyStatusFilter.occupied => all.where(isOccupied).toList(),
      PropertyStatusFilter.available => all.where(isAvailable).toList(),
    };

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text(_title, style: AppTextStyles.heading(color: theme.foreground, size: 18)),
      ),
      body: SafeArea(
        child: entries.isEmpty
            ? Center(
                child: Text(
                  'No properties here yet.',
                  style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6)),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: entries.length,
                    itemBuilder: (context, index) => _PropertyTile(
                      property: entries[index],
                      occupied: isOccupied(entries[index]),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PropertyDetailScreen(property: entries[index], theme: theme),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _PropertyTile extends StatelessWidget {
  const _PropertyTile({required this.property, required this.occupied, required this.onTap});

  final Property property;
  final bool occupied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: PropertyImage(path: property.image, width: 72, height: 72),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    property.title,
                    style: AppTextStyles.body(color: AppColors.navy, size: 15, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(property.location, style: AppTextStyles.body(color: AppColors.hintGrey, size: 13)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (occupied ? const Color(0xFF3FBF6A) : AppColors.gold).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      occupied ? 'Occupied' : 'Available',
                      style: AppTextStyles.body(
                        color: occupied ? const Color(0xFF1E8A4A) : AppColors.goldDark,
                        size: 11,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.navy),
          ],
        ),
      ),
    );
  }
}
