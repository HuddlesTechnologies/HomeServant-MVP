import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Shared by every admin tab's horizontal filter-chip row — replaces
/// what used to be separately duplicated as `_RoleChip`
/// (admin_users_tab.dart) and `_StatusChip` (admin_vendors_tab.dart),
/// which were identical apart from their name.
class AdminFilterChip extends StatelessWidget {
  const AdminFilterChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: Colors.white,
      selectedColor: AppColors.navy,
      labelStyle: AppTextStyles.body(color: selected ? Colors.white : AppColors.navy, size: 12.5, weight: FontWeight.w600),
      side: BorderSide.none,
    );
  }
}

/// The plain white, 14px-rounded card background repeated across the
/// admin tabs' list rows (users/vendors/properties/products/orders/
/// admins) — factored out so those `Container(decoration: ...)` calls
/// don't each redeclare the same `BoxDecoration`.
const adminCardDecoration = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(14)));
