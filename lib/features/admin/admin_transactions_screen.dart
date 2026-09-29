import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/admin_transaction.dart';
import '../../core/date_format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/thousands_separator.dart';
import '../../state/app_state.dart';
import '../dashboard/widgets/property_image.dart';
import 'admin_transaction_detail_screen.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_filter_chip.dart';
import 'widgets/admin_search_bar.dart';

/// Status colours for a transaction badge, darkened so the text reaches
/// 4.5:1 on its own 12% tint over the white card.
Color transactionStatusColor(TransactionStatus status) => switch (status) {
  TransactionStatus.credited => const Color(0xFF1E6B3A),
  TransactionStatus.held => const Color(0xFF8A5A0B),
  TransactionStatus.refunded => AppColors.navy,
};

/// Every admin tier (support, moderator, super admin): every successful
/// rent payment — tenant, landlord, property, when the tenant paid and when
/// the landlord was credited, and the Paystack references — with a search
/// bar across all of it. Tapping a row opens the full transaction, from
/// which the tenant, the landlord and the property each open in full.
/// Read-only: money actions stay on Payouts & Refunds. White cards, navy
/// text on the console's off-white background.
class AdminTransactionsScreen extends StatefulWidget {
  const AdminTransactionsScreen({super.key});

  @override
  State<AdminTransactionsScreen> createState() => _AdminTransactionsScreenState();
}

class _AdminTransactionsScreenState extends State<AdminTransactionsScreen> {
  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('credited', 'Credited'),
    ('held', 'Held'),
    ('refunded', 'Refunded'),
  ];

  List<AdminTransaction>? _items;
  int _total = 0;
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  String _search = '';
  String? _status;
  String? _error;

  /// Bumped on every fresh load, so a slow response to an older search
  /// can't overwrite the results of the one typed after it.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final page = await context.read<AppState>().admin.findTransactions(search: _search, status: _status);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _page = page.page;
        _hasMore = page.hasMore;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted && generation == _generation) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = "Couldn't load transactions.");
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await context.read<AppState>().admin.findTransactions(search: _search, status: _status, page: _page + 1);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = [...?_items, ...page.items];
        _total = page.total;
        _page = page.page;
        _hasMore = page.hasMore;
      });
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _open(AdminTransaction t) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminTransactionDetailScreen(transaction: t)));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      children: [
        AdminSearchBar(
          hint: 'Search reference, tenant, landlord, property or listing #',
          onChanged: (value) {
            _search = value;
            _load();
          },
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final (value, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdminFilterChip(
                    label: label,
                    selected: _status == value,
                    onTap: () {
                      setState(() => _status = value);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (items != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$_total transaction${_total == 1 ? '' : 's'}',
                style: AppTextStyles.body(color: AppColors.navy, size: 12.5, weight: FontWeight.w600),
              ),
            ),
          ),
        Expanded(
          child: items == null
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
                  color: AppColors.navy,
                  child: items.isEmpty
                      ? ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                _search.trim().isEmpty ? 'No successful transactions yet.' : 'No transactions match "${_search.trim()}".',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.body(color: AppColors.navy),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                          itemCount: items.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            if (index == items.length) {
                              return Center(
                                child: _loadingMore
                                    ? const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: CircularProgressIndicator(color: AppColors.navy),
                                      )
                                    : TextButton(
                                        onPressed: _loadMore,
                                        child: Text('Load more', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w700)),
                                      ),
                              );
                            }
                            return _TransactionCard(transaction: items[index], onTap: () => _open(items[index]));
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

/// One row: photo, property name, amount and status, who paid whom, when
/// the tenant paid and when the landlord was credited, and the reference.
/// Navy text (grey for labels) on white.
class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.transaction, required this.onTap});

  final AdminTransaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final property = t.property;
    final photo = property?.photos.firstOrNull;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: adminCardDecoration,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 64,
                height: 64,
                color: AppColors.offWhite,
                child: photo != null
                    ? PropertyImage(path: photo, width: 64, height: 64)
                    : const Icon(Icons.home_work_outlined, color: AppColors.hintGrey),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          property?.title ?? 'Property no longer listed',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        nairaLabelFromKobo(t.amountKobo),
                        style: AppTextStyles.body(color: AppColors.navy, size: 14, weight: FontWeight.w800),
                      ),
                    ],
                  ),
                  if (property != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Listing #${property.listingNumber} · ${property.location}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: AppColors.hintGrey, size: 12),
                    ),
                  ],
                  const SizedBox(height: 6),
                  AdminBadge(text: t.statusLabel, color: transactionStatusColor(t.status), size: AdminBadgeSize.small),
                  const SizedBox(height: 6),
                  _line('Tenant', t.tenant.name),
                  _line('Landlord', t.landlord.name),
                  _line('Paid', formatDateTime(t.paidAt)),
                  _line(
                    t.status == TransactionStatus.refunded ? 'Refunded' : 'Credited',
                    t.status == TransactionStatus.refunded
                        ? (t.refundedAt != null ? formatDateTime(t.refundedAt!) : '—')
                        : (t.creditedAt != null ? formatDateTime(t.creditedAt!) : 'Not yet'),
                  ),
                  _line('Ref', t.reference),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: Text(label, style: AppTextStyles.body(color: AppColors.hintGrey, size: 12))),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body(color: AppColors.navy, size: 12, weight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
