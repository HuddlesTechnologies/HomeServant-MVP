import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/vendor.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_permissions.dart';
import 'widgets/admin_search_bar.dart';

class AdminVendorsTab extends StatefulWidget {
  const AdminVendorsTab({super.key});

  @override
  State<AdminVendorsTab> createState() => _AdminVendorsTabState();
}

class _AdminVendorsTabState extends State<AdminVendorsTab> {
  List<AdminVendor>? _vendors;
  String _search = '';
  VendorApplicationStatus? _statusFilter = VendorApplicationStatus.pending;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await context.read<AppState>().admin.findVendors(
        status: _statusFilter?.apiValue,
        search: _search,
      );
      if (!mounted) return;
      setState(() {
        _vendors = page.items;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load vendors.");
    }
  }

  Future<void> _approve(AdminVendor vendor) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.approveVendor(vendor.id);
      messenger.showSnackBar(SnackBar(content: Text('${vendor.businessName} approved')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reject(AdminVendor vendor) async {
    final reasonController = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reject ${vendor.businessName}?', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
            const SizedBox(height: 8),
            Text('An email will be sent to the vendor with your reason.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Reason (optional)',
                filled: true,
                fillColor: AppColors.offWhite,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Reject', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.rejectVendor(vendor.id, reason: reasonController.text.trim());
      messenger.showSnackBar(SnackBar(content: Text('${vendor.businessName} rejected')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _toggleSuspend(AdminVendor vendor) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: vendor.isActive ? 'Suspend ${vendor.businessName}?' : 'Unsuspend ${vendor.businessName}?',
      body: vendor.isActive
          ? 'Their products will be hidden from the Marketplace until unsuspended.'
          : 'Their products will become visible in the Marketplace again.',
      actionLabel: vendor.isActive ? 'Suspend' : 'Unsuspend',
      destructive: vendor.isActive,
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (vendor.isActive) {
        await context.read<AppState>().admin.suspendVendor(vendor.id);
      } else {
        await context.read<AppState>().admin.unsuspendVendor(vendor.id);
      }
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendors = _vendors;
    return Column(
      children: [
        AdminSearchBar(
          hint: 'Search by business name',
          onChanged: (value) {
            _search = value;
            _load();
          },
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _StatusChip(label: 'Pending', selected: _statusFilter == VendorApplicationStatus.pending, onTap: () => setState(() { _statusFilter = VendorApplicationStatus.pending; _load(); })),
              const SizedBox(width: 8),
              _StatusChip(label: 'Approved', selected: _statusFilter == VendorApplicationStatus.approved, onTap: () => setState(() { _statusFilter = VendorApplicationStatus.approved; _load(); })),
              const SizedBox(width: 8),
              _StatusChip(label: 'Rejected', selected: _statusFilter == VendorApplicationStatus.rejected, onTap: () => setState(() { _statusFilter = VendorApplicationStatus.rejected; _load(); })),
              const SizedBox(width: 8),
              _StatusChip(label: 'All', selected: _statusFilter == null, onTap: () => setState(() { _statusFilter = null; _load(); })),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: vendors == null
              ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
              : vendors.isEmpty
              ? const Center(child: Text('No vendors found'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: vendors.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final vendor = vendors[index];
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(vendor.businessName, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 15)),
                                ),
                                _StatusBadge(status: vendor.status),
                                if (!vendor.isActive) ...[
                                  const SizedBox(width: 6),
                                  const _StatusBadge.custom(text: 'Suspended', color: Colors.redAccent),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${vendor.category.label} · ${vendor.state}', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
                            if (vendor.ownerEmail != null)
                              Text(vendor.ownerEmail!, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
                            if (vendor.status == VendorApplicationStatus.rejected && vendor.rejectionReason != null) ...[
                              const SizedBox(height: 6),
                              Text('Reason: ${vendor.rejectionReason}', style: AppTextStyles.body(color: Colors.redAccent, size: 12)),
                            ],
                            const SizedBox(height: 10),
                            if (!context.canModerate)
                              Text(
                                'View only — moderator level required to act on vendors',
                                style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5, weight: FontWeight.w600),
                              )
                            else
                            Row(
                              children: [
                                if (vendor.status == VendorApplicationStatus.pending) ...[
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _reject(vendor),
                                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                                      child: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _approve(vendor),
                                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy),
                                      child: const Text('Approve', style: TextStyle(color: Colors.white)),
                                    ),
                                  ),
                                ] else
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => _toggleSuspend(vendor),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: vendor.isActive ? Colors.redAccent : AppColors.navy),
                                      ),
                                      child: Text(
                                        vendor.isActive ? 'Suspend' : 'Unsuspend',
                                        style: TextStyle(color: vendor.isActive ? Colors.redAccent : AppColors.navy),
                                      ),
                                    ),
                                  ),
                              ],
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.selected, required this.onTap});

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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required VendorApplicationStatus status})
      : text = null,
        color = null,
        _status = status;

  const _StatusBadge.custom({required String text, required Color color})
      : text = text,
        color = color,
        _status = null;

  final VendorApplicationStatus? _status;
  final String? text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? switch (_status!) {
      VendorApplicationStatus.pending => Colors.orange,
      VendorApplicationStatus.approved => Colors.green,
      VendorApplicationStatus.rejected => Colors.redAccent,
    };
    final resolvedText = text ?? _status!.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: resolvedColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(resolvedText, style: AppTextStyles.body(color: resolvedColor, size: 10.5, weight: FontWeight.w700)),
    );
  }
}
