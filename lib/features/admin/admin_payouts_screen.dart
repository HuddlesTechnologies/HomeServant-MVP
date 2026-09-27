import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/stuck_payment.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import '../../widgets/verified_badge.dart';
import 'admin_user_detail_screen.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_confirm_sheet.dart';

const _red = Color(0xFFB42318);
const _amber = Color(0xFF8A5A0B);

/// Super admins: rent money that needs attention — payouts to landlords
/// that haven't gone out, and refunds to tenants that failed. Every action
/// goes through the same safeguards as automatic payments (one money action
/// at a time; Paystack is asked first whether it already happened), so
/// pressing a button twice can never pay or refund twice. White cards,
/// navy text. Badge text colours are darkened so they reach 4.5:1 on their tint.
class AdminPayoutsScreen extends StatefulWidget {
  const AdminPayoutsScreen({super.key});

  @override
  State<AdminPayoutsScreen> createState() => _AdminPayoutsScreenState();
}

class _AdminPayoutsScreenState extends State<AdminPayoutsScreen> {
  List<StuckPayment>? _items;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await context.read<AppState>().verification.stuckPayments();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String _naira(int kobo) => '₦${formatWithThousandsSeparator(kobo / 100)}';

  Future<void> _run(StuckPayment p, Future<String> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(p.paymentId));
    try {
      final message = await action();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(p.paymentId));
      await _load();
    }
  }

  Future<void> _retryPayout(StuckPayment p) async {
    final ok = await showAdminConfirmSheet(
      context,
      title: 'Send ${_naira(p.amountKobo)} to ${p.landlordName}?',
      body: 'HomeServant first checks with Paystack whether this payout already went out. If it did, it is simply marked as paid; '
          'nothing is sent twice.',
      actionLabel: 'Send payout',
      destructive: false,
    );
    if (ok != true || !mounted) return;
    final repo = context.read<AppState>().verification;
    await _run(p, () async {
      final result = await repo.retryPayout(p.paymentId);
      return result == 'ALREADY_PAID' ? 'This payout had already been sent; nothing more was sent.' : 'Payout sent to ${p.landlordName}.';
    });
  }

  Future<void> _retryRefund(StuckPayment p) async {
    final ok = await showAdminConfirmSheet(
      context,
      title: 'Retry the refund to ${p.tenantName ?? 'the tenant'}?',
      body: 'The same refund that failed is tried again (${_naira(p.amountKobo)}). HomeServant first checks with Paystack whether it '
          'already went through, so the tenant is never refunded twice.',
      actionLabel: 'Retry refund',
      destructive: false,
    );
    if (ok != true || !mounted) return;
    final repo = context.read<AppState>().verification;
    await _run(p, () async {
      final result = await repo.retryRefund(p.paymentId);
      return result == 'ALREADY_REFUNDED' ? 'This refund had already gone through; nothing more was sent.' : 'Tenant refunded.';
    });
  }

  Future<void> _refundTenant(StuckPayment p) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Refund ${p.tenantName ?? 'the tenant'} in full?',
      body: 'The tenant gets the full ${_naira(p.amountKobo)} back and the booking ends as Refunded. The landlord is not paid for it. '
          'The tenant can no longer request a refund themselves, and it can never be refunded twice.',
      actionLabel: 'Refund tenant',
      hint: 'Reason (the tenant and landlord see it)',
    );
    if (reason == null || !mounted) return;
    final repo = context.read<AppState>().verification;
    await _run(p, () async {
      await repo.refundTenant(p.paymentId, reason);
      return 'Tenant refunded in full.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.navy, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rent payouts to landlords and refunds to tenants that did not go through. Every button here is safe to press again: '
                    'Paystack is checked first, and only one money action can run for a payment at a time, so no one is ever paid or '
                    'refunded twice, and a payment can never be both paid out and refunded.',
                    style: AppTextStyles.body(color: AppColors.navy, size: 12.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body(color: _red)),
            )
          else if (items == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text('Nothing needs attention. Every payout and refund has gone through.', textAlign: TextAlign.center, style: AppTextStyles.body(color: AppColors.hintGrey)),
            )
          else
            for (final p in items) _card(p),
        ],
      ),
    );
  }

  Widget _card(StuckPayment p) {
    final busy = _busy.contains(p.paymentId) || p.inProgress;
    final isRefund = p.kind == StuckPaymentKind.refund;
    final color = p.reason == 'AWAITING_VERIFICATION' || p.reason == 'READY' ? _amber : _red;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${isRefund ? 'Refund to tenant' : 'Payout to landlord'} · ${_naira(p.amountKobo)}',
                  style: AppTextStyles.body(color: AppColors.navy, size: 15, weight: FontWeight.w700),
                ),
              ),
              AdminBadge(text: p.reasonLabel, color: color),
            ],
          ),
          if (p.propertyTitle != null) ...[
            const SizedBox(height: 4),
            Text(p.propertyTitle!, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5)),
          ],
          const SizedBox(height: 10),
          _row('Landlord', null, trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(p.landlordName, overflow: TextOverflow.ellipsis, style: AppTextStyles.body(color: AppColors.navy, size: 12.5))),
              if (p.landlordVerified) ...[const SizedBox(width: 4), const VerifiedBadge(textColor: AppColors.navy, label: null, size: 11)],
            ],
          )),
          if (!isRefund)
            _row('Bank', p.landlordAccountLast4 == null ? 'No bank account on file' : '${p.landlordBank ?? 'Bank'} ••••${p.landlordAccountLast4}'),
          if (p.tenantName != null) _row('Tenant', p.tenantName!),
          if (p.since != null) _row('Waiting since', formatShortDate(p.since!)),
          if (isRefund && p.requestedBy != null)
            _row('Asked for by', switch (p.requestedBy) { 'LANDLORD' => 'Landlord (rejected booking)', 'ADMIN' => 'An admin', _ => 'Tenant' }),
          if (p.attempts > 0) _row('Attempts', '${p.attempts}'),
          if (p.lastError != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(10)),
              child: Text('Last error: ${p.lastError}', style: AppTextStyles.body(color: AppColors.navy, size: 12)),
            ),
          ],
          if (p.reason == 'AWAITING_VERIFICATION') ...[
            const SizedBox(height: 6),
            Text(
              'Paid automatically once this landlord is verified (or if "Pay unverified landlords" is turned on in Platform Controls).',
              style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 12),
            ),
          ],
          const SizedBox(height: 12),
          if (busy)
            Row(
              children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.navy)),
                const SizedBox(width: 10),
                Text('In progress…', style: AppTextStyles.body(color: AppColors.navy, size: 13)),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (p.canRetry) _button('Retry payout', filled: true, onTap: () => _retryPayout(p)),
                if (p.canRetryRefund) _button('Retry refund', filled: true, onTap: () => _retryRefund(p)),
                if (p.canRefundTenant) _button('Refund tenant', onTap: () => _refundTenant(p)),
                _button('View landlord', onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminUserDetailScreen(userId: p.landlordId)));
                  if (mounted) _load();
                }),
              ],
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String? value, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))),
        Expanded(child: trailing ?? Text(value ?? '', style: AppTextStyles.body(color: AppColors.navy, size: 12.5))),
      ],
    ),
  );

  Widget _button(String label, {required VoidCallback onTap, bool filled = false}) => filled
      ? ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.navy,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: onTap,
          child: Text(label, style: AppTextStyles.body(color: Colors.white, size: 13, weight: FontWeight.w700)),
        )
      : OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.navy),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: onTap,
          child: Text(label, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w600)),
        );
}
