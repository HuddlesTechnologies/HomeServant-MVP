import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../api/models/admin_transaction.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../dashboard/property_gallery_screen.dart';
import '../dashboard/widgets/property_image.dart';
import 'admin_property_detail_screen.dart';
import 'admin_transactions_screen.dart';
import 'admin_user_detail_screen.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_filter_chip.dart';

/// One transaction in full: the property's photos and details, the payment
/// and its dates, the Paystack references (tap to copy), and the tenant
/// and landlord — each with a button to their full user page, and the
/// property with one to its full listing page. White cards with navy text
/// on the off-white background; white text only on the navy app bar and
/// filled buttons.
class AdminTransactionDetailScreen extends StatelessWidget {
  const AdminTransactionDetailScreen({super.key, required this.transaction});

  final AdminTransaction transaction;

  void _openUser(BuildContext context, String userId, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserDetailScreen(userId: userId, title: title)));
  }

  void _openProperty(BuildContext context, String propertyId) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminPropertyDetailScreen(propertyId: propertyId)));
  }

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final property = t.property;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Transaction', style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Section(
                title: 'Property',
                children: [
                  if (property == null)
                    Text('The property for this payment is no longer listed.', style: AppTextStyles.body(color: AppColors.navy, size: 13))
                  else ...[
                    if (property.photos.isNotEmpty) ...[_Photos(property: property), const SizedBox(height: 12)],
                    Text(property.title, style: AppTextStyles.body(color: AppColors.navy, size: 16, weight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    _Row('Listing #', '${property.listingNumber}'),
                    _Row('Location', [property.location, property.state].where((s) => s.isNotEmpty).join(', ')),
                    _Row('Type', _titleCase(property.category)),
                    _Row('Rooms', '${property.bedrooms} bed · ${property.bathrooms} bath'),
                    _Row('Price', '${nairaLabel(property.price)}${_perUnit(property.priceUnit)}'),
                    const SizedBox(height: 10),
                    _Button(label: 'View full property', icon: Icons.home_work_outlined, onTap: () => _openProperty(context, property.id)),
                  ],
                ],
              ),
              _Section(
                title: 'Payment',
                trailing: AdminBadge(text: t.statusLabel, color: transactionStatusColor(t.status)),
                children: [
                  _Row('Amount paid', nairaLabelFromKobo(t.amountKobo), bold: true),
                  _Row('HomeServant fee', nairaLabelFromKobo(t.platformFeeKobo)),
                  if (t.status != TransactionStatus.refunded) _Row("Landlord's share", nairaLabelFromKobo(t.landlordShareKobo)),
                  if (t.paymentPlan != null) _Row('Plan', t.paymentPlan == 'MONTHLY' ? 'Monthly rent' : 'Full payment'),
                  if (t.nights != null) _Row('Nights', '${t.nights}'),
                  _Row('Tenant paid', formatDateTime(t.paidAt)),
                  _Row(
                    'Landlord credited',
                    t.creditedAt != null
                        ? formatDateTime(t.creditedAt!)
                        : t.status == TransactionStatus.refunded
                        ? 'No: refunded to tenant'
                        : 'Not yet (held in escrow)',
                  ),
                  if (t.refundedAt != null) _Row('Refunded', formatDateTime(t.refundedAt!)),
                  if (t.refundReason != null) _Row('Refund reason', t.refundReason!),
                  if (t.leaseStartDate != null) _Row('Lease starts', formatShortDate(t.leaseStartDate!)),
                  if (t.leaseEndDate != null) _Row('Lease ends', formatShortDate(t.leaseEndDate!)),
                ],
              ),
              _Section(
                title: 'References',
                children: [
                  _CopyRow(label: 'Payment ref', value: t.reference),
                  if (t.payoutReference != null) _CopyRow(label: 'Payout ref', value: t.payoutReference!),
                  _CopyRow(label: 'Payment ID', value: t.id),
                ],
              ),
              _Section(
                title: 'Tenant (paid)',
                children: [
                  ..._person(t.tenant),
                  const SizedBox(height: 10),
                  _Button(label: 'View tenant', icon: Icons.person_outline_rounded, onTap: () => _openUser(context, t.tenant.id, 'Tenant Profile')),
                ],
              ),
              _Section(
                title: 'Landlord (credited)',
                children: [
                  ..._person(t.landlord),
                  _Row(
                    'Bank',
                    t.landlordAccountLast4 == null ? 'No bank account on file' : '${t.landlordBankName ?? 'Bank'} ••••${t.landlordAccountLast4}',
                  ),
                  if (t.landlordAccountName != null) _Row('Account name', t.landlordAccountName!),
                  const SizedBox(height: 10),
                  _Button(
                    label: 'View landlord',
                    icon: Icons.person_outline_rounded,
                    onTap: () => _openUser(context, t.landlord.id, 'Landlord Profile'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _person(TransactionPerson p) => [
    _Row('Name', p.name, bold: true),
    _Row('Email', p.email),
    if (p.phoneNumber != null && p.phoneNumber!.isNotEmpty) _Row('Phone', p.phoneNumber!),
  ];

  static String _titleCase(String value) =>
      value.isEmpty ? value : value.split('_').map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' ');

  static String _perUnit(String unit) => unit.isEmpty ? '' : ' / ${unit.toLowerCase()}';
}

/// Horizontal strip of every photo of the property; tapping one opens the
/// full-screen gallery at that photo.
class _Photos extends StatelessWidget {
  const _Photos({required this.property});

  final TransactionProperty property;

  @override
  Widget build(BuildContext context) {
    final photos = property.photos;
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PropertyGalleryScreen(images: photos, initialIndex: index, title: property.title)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 210,
              color: AppColors.offWhite,
              child: PropertyImage(path: photos[index], width: 210, height: 150),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white card with a navy section title.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: adminCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: AppTextStyles.body(color: AppColors.navy, size: 14.5, weight: FontWeight.w800))),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Grey label, navy value, on the white card.
class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 13))),
          Expanded(
            child: SelectableText(
              value,
              style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: bold ? FontWeight.w800 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// A reference with a copy button — support staff paste these into
/// Paystack's dashboard or a reply to the customer.
class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 13))),
          Expanded(
            child: SelectableText(value, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Copy',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.navy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
            },
          ),
        ],
      ),
    );
  }
}

/// Navy outlined pill button with navy label, on the white card.
class _Button extends StatelessWidget {
  const _Button({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.navy),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: AppColors.navy),
      label: Text(label, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w700)),
    );
  }
}
