import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../api/models/vendor.dart';
import '../../core/thousands_separator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_permissions.dart';

/// Full vendor profile — reached by tapping a row in AdminVendorsTab.
/// Shows the vendor's own catalog and the orders they've received on top
/// of the profile fields, and carries the same approve/reject/suspend/
/// unsuspend actions the tab offers (still MODERATOR+ gated).
class AdminVendorDetailScreen extends StatefulWidget {
  const AdminVendorDetailScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<AdminVendorDetailScreen> createState() => _AdminVendorDetailScreenState();
}

class _AdminVendorDetailScreenState extends State<AdminVendorDetailScreen> {
  AdminVendorDetail? _vendor;
  String? _error;
  bool _approving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final vendor = await context.read<AppState>().admin.vendorDetail(widget.vendorId);
      if (!mounted) return;
      setState(() {
        _vendor = vendor;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load this vendor.");
    }
  }

  Future<void> _approve(AdminVendorDetail vendor) async {
    if (_approving) return;
    setState(() => _approving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.approveVendor(vendor.id);
      messenger.showSnackBar(SnackBar(content: Text('${vendor.businessName} approved')));
      await _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _reject(AdminVendorDetail vendor) async {
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

  Future<void> _toggleSuspend(AdminVendorDetail vendor) async {
    final reason = await showAdminReasonSheet(
      context,
      title: !vendor.isSuspended ? 'Suspend ${vendor.businessName}?' : 'Unsuspend ${vendor.businessName}?',
      body: !vendor.isSuspended
          ? 'Their products will be hidden from the Marketplace until unsuspended. An email will be sent to the vendor with your reason.'
          : 'Their products will become visible in the Marketplace again. An email will be sent to the vendor with your reason.',
      actionLabel: !vendor.isSuspended ? 'Suspend' : 'Unsuspend',
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!vendor.isSuspended) {
        await context.read<AppState>().admin.suspendVendor(vendor.id, reason: reason);
      } else {
        await context.read<AppState>().admin.unsuspendVendor(vendor.id, reason: reason);
      }
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = _vendor;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Vendor Details', style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: vendor == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(vendor.businessName, style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
                            ),
                            _Badge(text: vendor.status.label, color: AppColors.navy),
                            if (vendor.isSuspended) ...[
                              const SizedBox(width: 6),
                              const _Badge(text: 'Suspended', color: Colors.redAccent),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        _Field('Category', vendor.category.label),
                        _Field('State', vendor.state),
                        _Field('Owner Email', vendor.ownerEmail ?? '—'),
                        _Field('CAC/RC Number', vendor.rcNumber ?? '—'),
                        if (vendor.status == VendorApplicationStatus.rejected && vendor.rejectionReason != null)
                          _Field('Rejection Reason', vendor.rejectionReason!),
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
                        Text('Payout Details', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                        const SizedBox(height: 10),
                        if (vendor.accountNumber == null)
                          Text('No payout details on file yet.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))
                        else ...[
                          _Field('Bank Name', vendor.bankName ?? '—'),
                          _Field('Account Number', vendor.accountNumber!),
                          _Field('Account Name', vendor.accountName ?? '—'),
                        ],
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
                        Text('Products (${vendor.products.length})', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                        const SizedBox(height: 10),
                        if (vendor.products.isEmpty)
                          Text('No products listed.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))
                        else
                          ...vendor.products.map(
                            (product) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(product.name, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 13)),
                                        Text(
                                          '${product.category.label} · Stock: ${product.stock}',
                                          style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text('₦${formatWithThousandsSeparator(product.price)}', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 13)),
                                      Text(
                                        product.isAvailable ? 'Available' : 'Unavailable',
                                        style: AppTextStyles.body(color: product.isAvailable ? Colors.green : Colors.redAccent, size: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
                        Text('Orders Received (${vendor.orders.length})', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                        const SizedBox(height: 10),
                        if (vendor.orders.isEmpty)
                          Text('No orders yet.', style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))
                        else
                          ...vendor.orders.map(
                            (order) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${order.productName} × ${order.quantity}',
                                          style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 13),
                                        ),
                                        Text(
                                          '${order.buyerName ?? 'Unknown buyer'} · ${order.status}',
                                          style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₦${formatWithThousandsSeparator(order.unitPrice * order.quantity)}',
                                    style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (context.canModerate) ...[
                    const SizedBox(height: 20),
                    if (vendor.status == VendorApplicationStatus.pending) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _reject(vendor),
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _approving ? null : () => _approve(vendor),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: _approving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Approve', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ] else
                      OutlinedButton(
                        onPressed: () => _toggleSuspend(vendor),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: BorderSide(color: !vendor.isSuspended ? Colors.redAccent : AppColors.navy),
                        ),
                        child: Text(
                          !vendor.isSuspended ? 'Suspend' : 'Unsuspend',
                          style: TextStyle(color: !vendor.isSuspended ? Colors.redAccent : AppColors.navy),
                        ),
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
