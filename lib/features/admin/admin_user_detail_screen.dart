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
import '../../widgets/upload_picker.dart';
import '../dashboard/chat_thread_screen.dart';
import 'widgets/admin_confirm_sheet.dart';
import 'widgets/admin_permissions.dart';
import '../../widgets/labeled_value_row.dart';
import 'widgets/admin_badge.dart';
import '../../widgets/verified_badge.dart';
import '../../api/models/verification.dart';
import 'widgets/admin_verification_card.dart';

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
      // Admin accounts can't be viewed or edited as users (the server
      // refuses too); they're managed on the Admins screen.
      if (user.role.isAdmin) {
        setState(() => _error = 'Admin accounts are managed on the Admins screen.');
        return;
      }
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
    final reason = await showAdminReasonSheet(
      context,
      title: 'Deactivate ${user.email}?',
      body: 'Their listings (if any) will be hidden and every session signed out. They can reactivate by logging back in.',
      actionLabel: 'Deactivate',
      hint: 'Reason (recorded in the admin activity log)',
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.deactivateUser(user.id, reason: reason);
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
                style: AppTextStyles.body(color: AppColors.navy, size: 14),
                decoration: InputDecoration(
                  labelText: 'Full name',
                  labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                  filled: true,
                  fillColor: AppColors.offWhite,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                style: AppTextStyles.body(color: AppColors.navy, size: 14),
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
                  filled: true,
                  fillColor: AppColors.offWhite,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                maxLines: 2,
                style: AppTextStyles.body(color: AppColors.navy, size: 14),
                decoration: InputDecoration(
                  labelText: 'House address',
                  labelStyle: AppTextStyles.body(color: AppColors.hintGrey, size: 13),
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

  Future<void> _removeProperty(AdminUserProperty property) async {
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

  /// Moderator+ (see `context.canModerate` gate at the button). Email is
  /// the login identifier, so this signs the account out everywhere —
  /// same reasoning as [_changePassword].
  Future<void> _changeEmail(AdminUserDetail user) async {
    final result = await showAdminValueReasonSheet(
      context,
      title: 'Change email for ${user.email}?',
      body: 'They will be signed out everywhere and must sign back in with the new email.',
      actionLabel: 'Change Email',
      valueLabel: 'New email',
      initialValue: user.email,
      valueValidator: (value) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value) ? null : 'Enter a valid email address',
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.updateUserEmail(user.id, newEmail: result.value, reason: result.reason);
      messenger.showSnackBar(SnackBar(content: Text('Email changed to ${result.value} — account signed out everywhere')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Moderator+. Sends the same reset-code email the self-service "forgot
  /// password" flow uses — the user finishes it themselves.
  Future<void> _sendPasswordReset(AdminUserDetail user) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Send a password reset to ${user.email}?',
      body: 'They will be emailed a reset code to use on the existing reset-password screen.',
      actionLabel: 'Send Reset',
      hint: 'Reason (recorded in the admin activity log)',
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.sendUserPasswordReset(user.id, reason: reason);
      messenger.showSnackBar(SnackBar(content: Text('Password reset code sent to ${user.email}')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Moderator+. Extreme-condition override — sets the password directly
  /// instead of emailing a reset code. Forces the user to set their own
  /// password on next login.
  Future<void> _changePassword(AdminUserDetail user) async {
    final result = await showAdminValueReasonSheet(
      context,
      title: 'Directly set a new password for ${user.email}?',
      body: 'For extreme cases only — they will be signed out everywhere and forced to set their own password on next login.',
      actionLabel: 'Change Password',
      valueLabel: 'New password',
      obscureValue: true,
      valueValidator: (value) => value.length >= 8 ? null : 'At least 8 characters',
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.setUserPassword(user.id, newPassword: result.value, reason: result.reason);
      messenger.showSnackBar(SnackBar(content: Text('Password changed for ${user.email} — account signed out everywhere')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Super admin only (see `context.isSuperAdmin` gate at the button).
  Future<void> _disable2fa(AdminUserDetail user) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Disable two-factor authentication for ${user.email}?',
      body: 'They will be able to sign in with just their password from now on.',
      actionLabel: 'Disable 2FA',
      hint: 'Reason (recorded in the admin activity log)',
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().admin.disableUserTwoFactor(user.id, reason: reason);
      messenger.showSnackBar(SnackBar(content: Text('Two-factor authentication disabled for ${user.email}')));
      _load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete(AdminUserDetail user) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Permanently delete ${user.email}?',
      body: "This can't be undone — their account and everything tied to it (listings, bookings, orders, messages) will be deleted.",
      actionLabel: 'Delete',
      hint: 'Reason (recorded in the admin activity log)',
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<AppState>().admin.deleteUser(user.id, reason: reason);
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
          ? Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body(color: AppColors.navy)),
                    )
                  : const CircularProgressIndicator(color: AppColors.navy),
            )
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: AppColors.offWhite,
                              backgroundImage: user.profilePhotoUrl != null ? imageProviderForPath(user.profilePhotoUrl!) : null,
                              child: user.profilePhotoUrl == null
                                  ? const Icon(Icons.person_outline_rounded, color: AppColors.hintGrey)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                user.fullName?.isNotEmpty == true ? user.fullName! : '(No name set)',
                                style: AppTextStyles.heading(color: AppColors.navy, size: 18),
                              ),
                            ),
                            Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                AdminBadge(text: user.role.adminLabel, color: AppColors.navy),
                                if (user.verificationStatus == VerificationStatus.approved)
                                  const VerifiedBadge(textColor: AppColors.navy, size: 11),
                                if (user.role != UserRole.vendor && user.vendorBusinessName != null)
                                  const AdminBadge(text: 'Also a Vendor', color: Colors.teal),
                                if (user.isDeactivated) const AdminBadge(text: 'Deactivated', color: Colors.redAccent),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        LabeledValueRow('Email', user.email),
                        LabeledValueRow('Phone Number', user.phoneNumber ?? '—'),
                        LabeledValueRow('House Address', user.houseAddress ?? '—'),
                        LabeledValueRow('Date of Birth', user.dateOfBirth != null ? formatShortDate(user.dateOfBirth!) : '—'),
                        LabeledValueRow('Email Verified', user.emailVerifiedAt != null ? formatShortDate(user.emailVerifiedAt!) : 'Not verified'),
                        LabeledValueRow('Two-Factor Auth', user.twoFactorEnabled ? 'Enabled' : 'Disabled'),
                        LabeledValueRow('Referral Code', user.referralCode ?? '—'),
                        LabeledValueRow('Joined', formatShortDate(user.createdAt)),
                        LabeledValueRow(
                          'Status',
                          user.isOnline
                              ? 'Active now'
                              : user.lastActiveAt != null
                                  ? 'Last active ${formatRelativeTime(user.lastActiveAt!)}'
                                  : 'Never connected',
                        ),
                        LabeledValueRow('Last Login IP', user.lastLoginIp ?? '—'),
                        LabeledValueRow('Device', user.lastLoginDeviceModel ?? '—'),
                      ],
                    ),
                  ),
                  if (user.role == UserRole.landlord || user.role == UserRole.tenant) ...[
                    const SizedBox(height: 12),
                    AdminVerificationCard(userId: user.id, isLandlord: user.role == UserRole.landlord),
                  ],
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
                          LabeledValueRow('Bank', user.bankName ?? '—'),
                          LabeledValueRow('Account Number', user.accountNumber ?? '—'),
                          LabeledValueRow('Account Name', user.accountName ?? '—'),
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
                          LabeledValueRow('Business Name', user.vendorBusinessName!),
                          LabeledValueRow('Status', user.vendorStatus ?? '—'),
                          LabeledValueRow('Active', (user.vendorIsActive ?? false) ? 'Yes' : 'No'),
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
                        LabeledValueRow('Properties Listed', '${user.propertiesCount}'),
                        LabeledValueRow('Bookings', '${user.bookingsCount}'),
                        LabeledValueRow('Marketplace Orders', '${user.marketplaceOrdersCount}'),
                        LabeledValueRow('Favorites', '${user.favoritesCount}'),
                        LabeledValueRow('Reviews Written', '${user.reviewsCount}'),
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
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: property.imageUrl != null
                                        ? Image(
                                            image: imageProviderForPath(property.imageUrl!),
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            width: 48,
                                            height: 48,
                                            color: AppColors.offWhite,
                                            child: const Icon(Icons.home_outlined, color: AppColors.hintGrey, size: 20),
                                          ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(property.title, style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600, size: 13)),
                                        Text(
                                          'Listing #${property.listingNumber}',
                                          style: AppTextStyles.body(color: AppColors.hintGrey, size: 11.5, weight: FontWeight.w600),
                                        ),
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
                                  if (context.canModerate)
                                    IconButton(
                                      onPressed: () => _removeProperty(property),
                                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                      tooltip: 'Remove listing',
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.only(left: 8),
                                      visualDensity: VisualDensity.compact,
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
                  if (context.canModerate) ...[
                    OutlinedButton(
                      onPressed: () => _sendPasswordReset(user),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColors.navy),
                        foregroundColor: AppColors.navy,
                      ),
                      child: Text('Send Password Reset', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _changePassword(user),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColors.navy),
                        foregroundColor: AppColors.navy,
                      ),
                      child: Text('Change Password', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () => _changeEmail(user),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColors.navy),
                        foregroundColor: AppColors.navy,
                      ),
                      child: Text('Change Email', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (context.isSuperAdmin && user.twoFactorEnabled) ...[
                    OutlinedButton(
                      onPressed: () => _disable2fa(user),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColors.navy),
                        foregroundColor: AppColors.navy,
                      ),
                      child: Text('Disable Two-Factor Authentication', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (context.canModerate && !user.isDeactivated)
                    OutlinedButton(
                      onPressed: () => _deactivate(user),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: const BorderSide(color: AppColors.navy),
                        foregroundColor: AppColors.navy,
                      ),
                      child: Text('Deactivate Account', style: AppTextStyles.button(color: AppColors.navy, size: 14)),
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
                      child: Text('Delete Account Permanently', style: AppTextStyles.button(color: Colors.redAccent, size: 14)),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

