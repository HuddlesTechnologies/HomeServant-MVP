import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_models.dart';
import '../../core/date_format.dart';
import '../../core/thousands_separator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_permissions.dart';

/// Full account detail for a single user — reached by tapping a row in
/// AdminUsersTab. Shows every field the backend will hand back (see
/// AdminService.findUserDetail) rather than the trimmed-down list-row
/// shape, and is where "Message" (start a console-to-user chat) lives.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  AdminUserDetail? _user;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await context.read<AppState>().admin.findUserDetail(widget.userId);
      if (!mounted) return;
      setState(() {
        _user = user;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = "Couldn't load this user.");
    }
  }

  Future<void> _message(AdminUserDetail user) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final thread = await context.read<AppState>().chat.openThread(recipientId: user.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            theme: DashboardTheme.midnight,
            contactName: user.fullName?.isNotEmpty == true ? user.fullName! : user.email,
            threadId: thread.id,
            adminViewOfUserId: user.id,
            showExportAction: true,
            otherParticipant: thread.otherParticipant,
          ),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deactivate(AdminUserDetail user) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: 'Deactivate ${user.email}?',
      body: 'Their listings (if any) will be hidden and every session signed out. They can reactivate by logging back in.',
      actionLabel: 'Deactivate',
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.deactivateUser(user.id);
      messenger.showSnackBar(SnackBar(content: Text('${user.email} deactivated')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Open to every admin tier — Support's one write power per the user's
  /// ruling is view+edit basic info, not delete/moderate. No
  /// `context.canModerate` gate here, unlike deactivate/delete below.
  Future<void> _edit(AdminUserDetail user) async {
    final nameController = TextEditingController(text: user.fullName ?? '');
    final phoneController = TextEditingController(text: user.phoneNumber ?? '');
    final addressController = TextEditingController(text: user.houseAddress ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit ${user.email}', style: AppTextStyles.heading(color: AppColors.navy, size: 18)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  filled: true,
                  fillColor: AppColors.offWhite,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  filled: true,
                  fillColor: AppColors.offWhite,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'House address',
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
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.navy),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: Text('Cancel', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      child: Text('Save', style: AppTextStyles.button(color: Colors.white, size: 14)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.updateUser(
        user.id,
        name: nameController.text.trim(),
        phone: phoneController.text.trim(),
        houseAddress: addressController.text.trim(),
      );
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(AdminUserDetail user) async {
    final confirmed = await showAdminConfirmSheet(
      context,
      title: 'Permanently delete ${user.email}?',
      body: "This can't be undone — their account and everything tied to it (listings, bookings, orders, messages) will be deleted.",
      actionLabel: 'Delete',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<AppState>().admin.deleteUser(user.id);
      messenger.showSnackBar(SnackBar(content: Text('${user.email} deleted')));
      navigator.pop();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('User Details', style: AppTextStyles.heading(color: Colors.white, size: 18)),
        actions: [
          if (user != null) ...[
            IconButton(
              onPressed: () => _edit(user),
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              tooltip: 'Edit',
            ),
            IconButton(
              onPressed: () => _message(user),
              icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white),
              tooltip: 'Message',
            ),
          ],
        ],
      ),
      body: user == null
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
                              child: Text(
                                user.fullName?.isNotEmpty == true ? user.fullName! : '(No name set)',
                                style: AppTextStyles.heading(color: AppColors.navy, size: 18),
                              ),
                            ),
                            _Badge(text: user.role.adminLabel, color: AppColors.navy),
                            if (user.isDeactivated) ...[
                              const SizedBox(width: 6),
                              const _Badge(text: 'Deactivated', color: Colors.redAccent),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        _Field('Email', user.email),
                        _Field('Phone Number', user.phoneNumber ?? '—'),
                        _Field('House Address', user.houseAddress ?? '—'),
                        _Field('Date of Birth', user.dateOfBirth != null ? formatShortDate(user.dateOfBirth!) : '—'),
                        _Field('Email Verified', user.emailVerifiedAt != null ? formatShortDate(user.emailVerifiedAt!) : 'Not verified'),
                        _Field('Two-Factor Auth', user.twoFactorEnabled ? 'Enabled' : 'Disabled'),
                        _Field('Referral Code', user.referralCode ?? '—'),
                        _Field('Joined', formatShortDate(user.createdAt)),
                        _Field(
                          'Status',
                          user.isOnline
                              ? 'Active now'
                              : user.lastActiveAt != null
                                  ? 'Last active ${formatRelativeTime(user.lastActiveAt!)}'
                                  : 'Never connected',
                        ),
                        _Field('Last Login IP', user.lastLoginIp ?? '—'),
                        _Field('Device', user.lastLoginDeviceModel ?? '—'),
                      ],
                    ),
                  ),
                  if (user.role == UserRole.landlord) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Payout Account', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                          const SizedBox(height: 10),
                          _Field('Bank', user.bankName ?? '—'),
                          _Field('Account Number', user.accountNumber ?? '—'),
                          _Field('Account Name', user.accountName ?? '—'),
                        ],
                      ),
                    ),
                  ],
                  if (user.vendorBusinessName != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Vendor Shop', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                          const SizedBox(height: 10),
                          _Field('Business Name', user.vendorBusinessName!),
                          _Field('Status', user.vendorStatus ?? '—'),
                          _Field('Active', (user.vendorIsActive ?? false) ? 'Yes' : 'No'),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Activity', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                        const SizedBox(height: 10),
                        _Field('Properties Listed', '${user.propertiesCount}'),
                        _Field('Bookings', '${user.bookingsCount}'),
                        _Field('Marketplace Orders', '${user.marketplaceOrdersCount}'),
                        _Field('Favorites', '${user.favoritesCount}'),
                        _Field('Reviews Written', '${user.reviewsCount}'),
                      ],
                    ),
                  ),
                  if (user.properties.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Properties Listed', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                          const SizedBox(height: 10),
                          ...user.properties.map(
                            (property) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(property.title, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 13)),
                                        Text(
                                          property.isOccupied ? 'Occupied' : 'Vacant',
                                          style: AppTextStyles.body(color: property.isOccupied ? Colors.orange : Colors.green, size: 11.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₦${formatWithThousandsSeparator(property.price)}/${property.priceUnit.toLowerCase()}',
                                    style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (user.bookings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Booking History', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                          const SizedBox(height: 10),
                          ...user.bookings.map(
                            (booking) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(booking.propertyTitle, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 13)),
                                        Text(
                                          booking.requestedDate != null
                                              ? 'Requested ${formatShortDate(booking.requestedDate!)} · ${booking.status}'
                                              : booking.status,
                                          style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '₦${formatWithThousandsSeparator(booking.price)}/${booking.priceUnit.toLowerCase()}',
                                    style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (user.marketplaceOrders.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Marketplace Orders', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 14)),
                          const SizedBox(height: 10),
                          ...user.marketplaceOrders.map(
                            (order) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(formatShortDate(order.createdAt), style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5)),
                                  const SizedBox(height: 4),
                                  ...order.items.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '${item.productName} × ${item.quantity}',
                                                  style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 13),
                                                ),
                                                Text(
                                                  '${item.vendorBusinessName ?? 'Unknown vendor'} · ${item.status}',
                                                  style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '₦${formatWithThousandsSeparator(item.unitPrice * item.quantity)}',
                                            style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (!user.isDeactivated)
                    OutlinedButton(
                      onPressed: () => _deactivate(user),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: const Text('Deactivate Account'),
                    ),
                  if (context.canModerate) ...[
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _delete(user),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: Colors.redAccent),
                        foregroundColor: Colors.redAccent,
                      ),
                      child: const Text('Delete Account Permanently'),
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
