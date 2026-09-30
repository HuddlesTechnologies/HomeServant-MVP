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

/// Moderators and super admins: rent money that needs attention — payouts to landlords
/// that haven't gone out (or that an admin paused), and refunds to tenants
/// that failed. A payout can be paused, resumed or cancelled here. Every action
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

  /// HomeServant's Paystack balance (payouts are sent from it); null while
  /// loading or when Paystack couldn't be asked.
  int? _balanceKobo;
  bool _balanceLoaded = false;

  /// 'test', 'live' or 'unknown' — which Paystack balance the server's key
  /// reads. Test and live are separate: money added in one isn't in the other.
  String _mode = 'unknown';
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final repo = context.read<AppState>().verification;
    // Best-effort: the list still shows if the balance can't be read.
    repo.paystackBalance().then<({int? balanceKobo, String mode})?>((b) => b).catchError((_) => null).then((b) {
      if (!mounted) return;
      setState(() {
        _balanceKobo = b?.balanceKobo;
        _mode = b?.mode ?? 'unknown';
        _balanceLoaded = true;
      });
    });
    try {
      final items = await repo.stuckPayments();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Payouts waiting only because the Paystack balance is too low (the
  /// server's error starts with this; see backend LOW_BALANCE_ERROR).
  bool _blockedByBalance(StuckPayment p) =>
      p.kind == StuckPaymentKind.payout && (p.lastError?.contains("Paystack balance is too low") ?? false);

  /// Paystack balance, plus — when payouts are stuck on it — what to do.
  /// Navy text on white; the warning in the screen's darkened amber.
  Widget _balanceCard(List<StuckPayment>? items) {
    final blocked = items?.where(_blockedByBalance).toList() ?? const <StuckPayment>[];
    final owedKobo = blocked.fold<int>(0, (sum, p) => sum + p.amountKobo);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: blocked.isEmpty ? null : Border.all(color: _amber, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined, color: AppColors.navy, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  !_balanceLoaded
                      ? 'Paystack balance: checking…'
                      : _balanceKobo == null
                      ? "Paystack balance: couldn't be checked right now"
                      : 'Paystack balance: ${nairaLabelFromKobo(_balanceKobo!)}',
                  style: AppTextStyles.body(color: AppColors.navy, size: 13.5, weight: FontWeight.w700),
                ),
              ),
              if (_balanceLoaded) _modeChip(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Payouts to landlords are sent from this balance, so it has to hold at least the amount being paid out. '
            '${_mode == 'test' ? 'The server is using a TEST key: only the test balance counts, and no real money moves. ' : ''}'
            '${_mode == 'unknown' ? "The server's Paystack key isn't a normal test or live key; check PAYSTACK_SECRET_KEY. " : ''}'
            'Money added in the Paystack dashboard in the other mode (test vs live) is not available here.',
            style: AppTextStyles.body(color: AppColors.navy, size: 12.5),
          ),
          if (blocked.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${blocked.length} payout${blocked.length == 1 ? '' : 's'} (${nairaLabelFromKobo(owedKobo)}) '
              '${blocked.length == 1 ? 'is' : 'are'} waiting for enough balance. Fund the Paystack balance, or ask Paystack to keep '
              'collected payments in the balance instead of settling them to the bank. They are retried automatically every '
              '30 minutes, so Retry is only needed if you want to send one straight away.',
              style: AppTextStyles.body(color: _amber, size: 12.5, weight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

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
      title: 'Send ${nairaLabelFromKobo(p.amountKobo)} to ${p.landlordName}?',
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
      body: 'The same refund that failed is tried again (${nairaLabelFromKobo(p.amountKobo)}). HomeServant first checks with Paystack whether it '
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
      body: 'The tenant gets the full ${nairaLabelFromKobo(p.amountKobo)} back and the booking ends as Refunded. The landlord is not paid for it. '
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

  Future<void> _pausePayout(StuckPayment p) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Pause the payout to ${p.landlordName}?',
      body: 'Nothing is sent to the landlord (${nairaLabelFromKobo(p.amountKobo)}) until an admin resumes it: not on move-in, not on '
          'verification, and not by Retry. The money stays held by HomeServant.',
      actionLabel: 'Pause payout',
      hint: 'Reason (only admins see it)',
    );
    if (reason == null || !mounted) return;
    final repo = context.read<AppState>().verification;
    await _run(p, () async {
      await repo.pausePayout(p.paymentId, reason);
      return 'Payout paused.';
    });
  }

  Future<void> _resumePayout(StuckPayment p) async {
    final ok = await showAdminConfirmSheet(
      context,
      title: 'Resume the payout to ${p.landlordName}?',
      body: 'If the landlord is owed it now, ${nairaLabelFromKobo(p.amountKobo)} is sent straight away (Paystack is checked first, so it is '
          'never sent twice). Otherwise it is paid when it comes due, as usual.',
      actionLabel: 'Resume payout',
      destructive: false,
    );
    if (ok != true || !mounted) return;
    final repo = context.read<AppState>().verification;
    await _run(p, () async {
      final result = await repo.resumePayout(p.paymentId);
      if (result.sent) return 'Payout resumed and sent to ${p.landlordName}.';
      return result.message == null ? 'Payout resumed.' : 'Payout resumed, but not sent yet: ${result.message}';
    });
  }

  Future<void> _cancelPayout(StuckPayment p) async {
    final reason = await showAdminReasonSheet(
      context,
      title: 'Cancel the payout to ${p.landlordName}?',
      body: 'The landlord will never be sent this ${nairaLabelFromKobo(p.amountKobo)}. It stays held by HomeServant and leaves this list. '
          'This can\'t be undone.${p.canRefundTenant ? ' To give the money back to the tenant instead, use Refund tenant.' : ''}',
      actionLabel: 'Cancel payout',
      hint: 'Reason (the landlord sees it)',
    );
    if (reason == null || !mounted) return;
    final repo = context.read<AppState>().verification;
    await _run(p, () async {
      await repo.cancelPayout(p.paymentId, reason);
      return 'Payout cancelled.';
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
          _balanceCard(items),
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

  /// "Live mode" / "Test mode" pill. Text in the same colour as its tint
  /// (green for live, the screen's amber for test/unknown), darkened so it
  /// reads on the tinted white.
  Widget _modeChip() {
    final (label, color) = switch (_mode) {
      'live' => ('Live mode', const Color(0xFF1E6B3A)),
      'test' => ('Test mode', _amber),
      _ => ('Mode unknown', _red),
    };
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: AppTextStyles.body(color: color, size: 11.5, weight: FontWeight.w800)),
    );
  }

  Widget _card(StuckPayment p) {
    final busy = _busy.contains(p.paymentId) || p.inProgress;
    final isRefund = p.kind == StuckPaymentKind.refund;
    final color = p.reason == 'AWAITING_VERIFICATION' || p.reason == 'READY' || p.reason == 'PAUSED' ? _amber : _red;
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
                  '${isRefund ? 'Refund to tenant' : 'Payout to landlord'} · ${nairaLabelFromKobo(p.amountKobo)}',
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
          if (p.pausedAt != null) _row('Paused on', formatShortDate(p.pausedAt!)),
          if (p.pauseReason != null && p.pauseReason!.isNotEmpty) _row('Pause note', p.pauseReason!),
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
                if (p.canResume) _button('Resume payout', filled: true, onTap: () => _resumePayout(p)),
                if (p.canRefundTenant) _button('Refund tenant', onTap: () => _refundTenant(p)),
                if (p.canPause) _button('Pause payout', onTap: () => _pausePayout(p)),
                if (p.canCancel) _button('Cancel payout', danger: true, onTap: () => _cancelPayout(p)),
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

  /// [danger]: outlined in the screen's red, for an action that can't be
  /// undone (red text on white).
  Widget _button(String label, {required VoidCallback onTap, bool filled = false, bool danger = false}) => filled
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
            side: BorderSide(color: danger ? _red : AppColors.navy),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: onTap,
          child: Text(label, style: AppTextStyles.body(color: danger ? _red : AppColors.navy, size: 13, weight: FontWeight.w600)),
        );
}
