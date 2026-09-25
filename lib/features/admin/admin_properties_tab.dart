import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_permissions.dart';
import 'widgets/admin_search_bar.dart';

class AdminPropertiesTab extends StatefulWidget {
  const AdminPropertiesTab({super.key});

  @override
  State<AdminPropertiesTab> createState() => _AdminPropertiesTabState();
}

class _AdminPropertiesTabState extends State<AdminPropertiesTab> {
  List<AdminProperty>? _properties;
  String _search = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await context.read<AppState>().admin.findProperties(search: _search);
      if (!mounted) return;
      setState(() {
        _properties = page.items;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load properties.");
    }
  }

  Future<void> _remove(AdminProperty property) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Remove "${property.title}"?',
      body: "This can't be undone — the listing and any bookings/reviews on it will be permanently deleted. The landlord is emailed the reason you give below.",
      actionLabel: 'Remove',
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.removeProperty(property.id, reason: reason);
      messenger.showSnackBar(SnackBar(content: Text('${property.title} removed')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _relist(AdminProperty property) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: 'Re-list "${property.title}"?',
      body:
          "This property is currently occupied and locked from re-listing by its landlord. This override makes "
          "it listable again — only do this if you've confirmed with the landlord that it's actually available.",
      actionLabel: 'Re-list',
      destructive: false,
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

  @override
  Widget build(BuildContext context) {
    final properties = _properties;
    return Column(
      children: [
        AdminSearchBar(
          hint: 'Search by title or location',
          onChanged: (value) {
            _search = value;
            _load();
          },
        ),
        Expanded(
          child: properties == null
              ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
              : properties.isEmpty
              ? const Center(child: Text('No properties found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: properties.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final property = properties[index];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: adminCardDecoration,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(property.title, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                                  const SizedBox(height: 2),
                                  Text(property.location, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₦${formatWithThousandsSeparator(property.price)} · ${property.landlordName ?? property.landlordEmail ?? 'Unknown landlord'}',
                                    style: AppTextStyles.body(color: AppColors.hintGrey, size: 12),
                                  ),
                                  if (property.isOccupied) ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Occupied — locked from re-listing',
                                        style: TextStyle(color: Colors.orange, fontSize: 10.5, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (context.canModerate && property.isOccupied)
                              IconButton(
                                onPressed: () => _relist(property),
                                icon: const Icon(Icons.lock_open_rounded, color: Colors.orange),
                                tooltip: 'Re-list (override occupied lock)',
                              ),
                            if (context.canModerate)
                              IconButton(
                                onPressed: () => _remove(property),
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
