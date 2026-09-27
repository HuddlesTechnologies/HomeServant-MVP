import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/platform_settings.dart';
import '../../core/date_format.dart';
import '../../core/thousands_separator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import '../../widgets/verified_badge.dart';
import 'widgets/admin_confirm_sheet.dart';

/// Super admins: platform-wide switches. Navy text on white cards.
class AdminPlatformControlsScreen extends StatefulWidget {
  const AdminPlatformControlsScreen({super.key});

  @override
  State<AdminPlatformControlsScreen> createState() => _AdminPlatformControlsScreenState();
}

class _AdminPlatformControlsScreenState extends State<AdminPlatformControlsScreen> {
  PlatformSettings? _settings;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final settings = await context.read<AppState>().verification.platformSettings();
      if (mounted) setState(() => _settings = settings);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _toggle(bool value) async {
    final s = _settings;
    if (s == null) return;
    final ok = await showAdminConfirmSheet(
      context,
      title: value ? 'Only show verified landlords?' : 'Show all landlords again?',
      body: value
          ? '${s.unverifiedListings} of ${s.totalListings} listings are from landlords who are not verified. '
                'They will disappear from browsing and search, and can\'t be booked, until their landlord is verified. '
                'Landlords still see their own listings, and existing tenancies are not affected.'
          : 'Listings from unverified landlords will appear in browsing and search again and can be booked.',
      actionLabel: value ? 'Turn on' : 'Turn off',
      destructive: false,
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final updated = await context.read<AppState>().verification.setRequireVerifiedLandlords(value);
      if (mounted) setState(() => _settings = updated);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center, style: AppTextStyles.body(color: const Color(0xFFC53030))),
            )
          else if (s == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.verified_rounded, color: verifiedBlue, size: 20),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Only verified landlords',
                                    style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 15),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'When on, tenants only see (and can only book) listings from landlords whose identity '
                              'HomeServant has verified. Landlords always see their own listings; current tenancies are untouched.',
                              style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _saving
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
                            )
                          : Switch(
                              value: s.requireVerifiedLandlords,
                              onChanged: _toggle,
                              activeColor: Colors.white,
                              activeTrackColor: AppColors.navy,
                              inactiveThumbColor: AppColors.navy,
                              inactiveTrackColor: AppColors.offWhite,
                            ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _stat('Status', s.requireVerifiedLandlords ? 'On: unverified listings are hidden' : 'Off: every listing is shown'),
                        _stat('Verified landlords', '${s.verifiedLandlords} (of ${s.landlordsWithListings} with listings)'),
                        _stat(
                          s.requireVerifiedLandlords ? 'Listings hidden' : 'Would be hidden',
                          '${s.unverifiedListings} of ${s.totalListings}',
                        ),
                      ],
                    ),
                  ),
                  if (s.updatedByName != null && s.updatedAt != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Last changed by ${s.updatedByName} on ${formatShortDate(s.updatedAt!)}',
                      style: AppTextStyles.body(color: AppColors.hintGrey, size: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _payoutCard(s),
          ],
        ],
      ),
    );
  }

  String _naira(int kobo) => '₦${formatWithThousandsSeparator(kobo / 100)}';

  Future<void> _togglePay(bool pay) async {
    final s = _settings;
    if (s == null) return;
    final ok = await showAdminConfirmSheet(
      context,
      title: pay ? 'Pay unverified landlords again?' : 'Hold payouts to unverified landlords?',
      body: pay
          ? (s.heldPayoutCount > 0
                ? 'The ${s.heldPayoutCount} payout${s.heldPayoutCount == 1 ? '' : 's'} held right now (${_naira(s.heldPayoutKobo)}) will be sent to '
                      '${s.heldPayoutLandlords == 1 ? 'the landlord' : 'those ${s.heldPayoutLandlords} landlords'} straight away, and future payouts go out as normal.'
                : 'Future payouts go out to every landlord as normal, verified or not.')
          : 'From now on, when a tenant moves in, pays for a shortlet or renews with a landlord who is not verified, HomeServant keeps the money '
                'instead of paying the landlord. Tenants are not affected. Each landlord is told why, and their money is sent automatically once they are verified.',
      actionLabel: pay ? 'Pay them' : 'Hold payouts',
      destructive: false,
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final updated = await context.read<AppState>().verification.setPayUnverifiedLandlords(pay);
      if (mounted) setState(() => _settings = updated);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "Pay unverified landlords" — what ON and OFF each do, in plain words,
  /// plus what is held right now. White card, navy text.
  Widget _payoutCard(PlatformSettings s) {
    final on = s.payUnverifiedLandlords;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, color: AppColors.navy, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Pay unverified landlords',
                        style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700, size: 15),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _saving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.navy)),
                    )
                  : Switch(
                      value: on,
                      onChanged: _togglePay,
                      activeColor: Colors.white,
                      activeTrackColor: AppColors.navy,
                      inactiveThumbColor: AppColors.navy,
                      inactiveTrackColor: AppColors.offWhite,
                    ),
            ],
          ),
          const SizedBox(height: 8),
          _explain(
            'ON',
            'Landlords are paid as normal when a tenant moves in, pays for a shortlet or renews, whether or not their identity is verified.',
            highlighted: on,
          ),
          const SizedBox(height: 8),
          _explain(
            'OFF',
            'Landlords must be verified before they are paid. Payouts to unverified landlords are held by HomeServant, and each landlord is '
                'told to get verified. The money is sent automatically as soon as they are verified, or to everyone if you turn this back ON.',
            highlighted: !on,
          ),
          const SizedBox(height: 8),
          Text(
            'Tenants are never affected: they still move in, stay and renew as normal, and are not notified. Verified landlords are always paid.',
            style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.75), size: 12.5),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.offWhite, borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stat('Status', on ? 'ON: everyone is paid' : 'OFF: unverified landlords\' payouts are held'),
                _stat(
                  'Held right now',
                  s.heldPayoutCount == 0
                      ? 'Nothing'
                      : '${s.heldPayoutCount} payout${s.heldPayoutCount == 1 ? '' : 's'}, ${_naira(s.heldPayoutKobo)} '
                            '(${s.heldPayoutLandlords} landlord${s.heldPayoutLandlords == 1 ? '' : 's'})',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One ON/OFF line; the current state gets a navy outline.
  Widget _explain(String label, String text, {required bool highlighted}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: highlighted ? AppColors.navy : AppColors.navy.withValues(alpha: 0.12), width: highlighted ? 1.4 : 1),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: highlighted ? AppColors.navy : AppColors.offWhite,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: AppTextStyles.body(color: highlighted ? Colors.white : AppColors.navy, size: 11, weight: FontWeight.w700)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: AppTextStyles.body(color: AppColors.navy, size: 12.5))),
      ],
    ),
  );

  Widget _stat(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12.5))),
        Expanded(child: Text(value, style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w600))),
      ],
    ),
  );
}
