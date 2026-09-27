import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../api/api_exception.dart';
import '../api/models/bank.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../models/dashboard_theme.dart';
import '../state/app_state.dart';
import 'dashboard_page_scaffold.dart';
import 'pill_button.dart';
import 'pill_text_field.dart';

/// The payout account currently on file, if any.
typedef SavedBankAccount = ({String? bankCode, String? accountNumber, String? accountName});

/// Every color the screen draws, as contrast-checked pairs: [text] on
/// [background], [fieldText] on [fieldFill], [onAccent] on [accent],
/// [sheetText] on [sheetBackground].
class BankDetailsPalette {
  const BankDetailsPalette({
    required this.background,
    required this.title,
    required this.text,
    required this.accent,
    required this.onAccent,
    required this.fieldFill,
    required this.fieldText,
    required this.fieldIcon,
    required this.sheetBackground,
    required this.sheetText,
    required this.sheetSearchFill,
  });

  final Color background;
  final Color title;
  final Color text;
  final Color accent;
  final Color onAccent;
  final Color fieldFill;
  final Color fieldText;
  final Color fieldIcon;
  final Color sheetBackground;
  final Color sheetText;
  final Color sheetSearchFill;
}

/// Lets a landlord or vendor set the bank account their payouts are
/// credited to. The account number is resolved against Paystack as soon as
/// a bank is picked and 10 digits are entered, so they see and confirm the
/// real account holder's name before saving — the same name the server
/// independently re-resolves and actually persists.
///
/// Landlords and vendors used to have two copies of this screen that
/// differed only in colors, where the saved account comes from/goes to,
/// and the intro text; those are the parameters now.
class BankDetailsScreen extends StatefulWidget {
  const BankDetailsScreen._({
    required this.palette,
    required this.intro,
    required this.load,
    required this.save,
  });

  /// Landlords draw the fixed navy/gold brand palette, not a switchable
  /// DashboardTheme, and their account is already on [AppState].
  factory BankDetailsScreen.landlord() => BankDetailsScreen._(
    palette: const BankDetailsPalette(
      background: AppColors.navy,
      title: AppColors.gold,
      text: Colors.white,
      accent: AppColors.gold,
      onAccent: AppColors.navy,
      fieldFill: AppColors.white,
      fieldText: AppColors.navy,
      fieldIcon: AppColors.inputFieldGrey,
      sheetBackground: AppColors.navyDark,
      sheetText: Colors.white,
      sheetSearchFill: Color(0x14FFFFFF),
    ),
    intro:
        'This is the account that will be credited whenever a tenant pays you. Double-check the '
        'account holder name below matches yours before saving.',
    load: (appState) async =>
        (bankCode: appState.bankCode, accountNumber: appState.accountNumber, accountName: appState.accountName),
    save: (appState, bankCode, accountNumber) =>
        appState.updateBankDetails(bankCode: bankCode, accountNumber: accountNumber),
  );

  /// Vendors follow their DashboardTheme; their account lives on the
  /// vendor profile, fetched fresh (see VendorsRepository.update).
  factory BankDetailsScreen.vendor(DashboardTheme theme) => BankDetailsScreen._(
    palette: BankDetailsPalette(
      background: theme.background,
      title: theme.foreground,
      text: theme.foreground,
      accent: theme.accent,
      onAccent: theme.onAccent,
      fieldFill: theme.surface,
      fieldText: theme.onSurface,
      fieldIcon: theme.onSurface.withValues(alpha: 0.4),
      sheetBackground: theme.surface,
      sheetText: theme.onSurface,
      sheetSearchFill: theme.onSurface.withValues(alpha: 0.06),
    ),
    intro:
        'This is the account that will be credited once a buyer confirms an order was received. '
        'Double-check the account holder name below matches yours before saving.',
    load: (appState) async {
      final vendor = await appState.vendors.me();
      return (bankCode: vendor.bankCode, accountNumber: vendor.accountNumber, accountName: vendor.accountName);
    },
    save: (appState, bankCode, accountNumber) =>
        appState.vendors.update(bankCode: bankCode, accountNumber: accountNumber),
  );

  final BankDetailsPalette palette;
  final String intro;
  final Future<SavedBankAccount> Function(AppState appState) load;
  final Future<void> Function(AppState appState, String bankCode, String accountNumber) save;

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _accountNumber = TextEditingController();
  List<Bank>? _banks;
  Bank? _selectedBank;
  String? _resolvedAccountName;
  bool _loadingAccount = true;
  bool _resolving = false;
  bool _saving = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadAccount();
    _accountNumber.addListener(_onAccountNumberChanged);
  }

  Future<void> _loadAccount() async {
    try {
      final saved = await widget.load(context.read<AppState>());
      if (!mounted) return;
      _accountNumber.text = saved.accountNumber ?? '';
      _resolvedAccountName = saved.accountName;
      await _loadBanks(preselectCode: saved.bankCode);
    } catch (_) {
      if (!mounted) return;
      await _loadBanks();
    } finally {
      if (mounted) setState(() => _loadingAccount = false);
    }
  }

  Future<void> _loadBanks({String? preselectCode}) async {
    try {
      final banks = await context.read<AppState>().paystack.listBanks();
      if (!mounted) return;
      setState(() {
        _banks = banks;
        if (preselectCode != null) {
          _selectedBank = banks.where((b) => b.code == preselectCode).firstOrNull;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _banks = []);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _accountNumber.removeListener(_onAccountNumberChanged);
    _accountNumber.dispose();
    super.dispose();
  }

  void _onAccountNumberChanged() {
    setState(() => _resolvedAccountName = null);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _tryResolve);
  }

  Future<void> _tryResolve() async {
    final bank = _selectedBank;
    final accountNumber = _accountNumber.text.trim();
    if (bank == null || accountNumber.length != 10) return;
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final resolved = await context.read<AppState>().paystack.resolveAccount(
        accountNumber: accountNumber,
        bankCode: bank.code,
      );
      if (!mounted) return;
      setState(() => _resolvedAccountName = resolved.accountName);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _pickBank() async {
    final banks = _banks;
    if (banks == null || banks.isEmpty) return;
    final palette = widget.palette;
    final result = await showModalBottomSheet<Bank>(
      context: context,
      backgroundColor: palette.sheetBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _BankPickerSheet(banks: banks, palette: palette),
    );
    if (result != null) {
      setState(() {
        _selectedBank = result;
        _resolvedAccountName = null;
      });
      _tryResolve();
    }
  }

  Future<void> _save() async {
    final bank = _selectedBank;
    if (bank == null || _resolvedAccountName == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.save(context.read<AppState>(), bank.code, _accountNumber.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bank details saved')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final canSave = _selectedBank != null && _resolvedAccountName != null && !_resolving;
    return DashboardPageScaffold(
      background: palette.background,
      foreground: palette.title,
      title: 'Bank Details',
      body: SafeArea(
        child: _loadingAccount
            ? Center(child: CircularProgressIndicator(color: palette.accent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      widget.intro,
                      style: AppTextStyles.body(color: palette.text.withValues(alpha: 0.85), size: 13),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Bank', style: AppTextStyles.body(color: palette.text, weight: FontWeight.w600, size: 13.5)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _banks == null ? null : _pickBank,
                    borderRadius: BorderRadius.circular(28),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                      decoration: BoxDecoration(color: palette.fieldFill, borderRadius: BorderRadius.circular(28)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedBank?.name ?? (_banks == null ? 'Loading banks…' : 'Select your bank'),
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body(color: palette.fieldText, size: 15),
                            ),
                          ),
                          Icon(Icons.keyboard_arrow_down_rounded, color: palette.fieldIcon),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Account Number',
                    style: AppTextStyles.body(color: palette.text, weight: FontWeight.w600, size: 13.5),
                  ),
                  const SizedBox(height: 8),
                  PillTextField(
                    hint: '10-digit account number',
                    controller: _accountNumber,
                    keyboardType: TextInputType.number,
                    fillColor: palette.fieldFill,
                    textColor: palette.fieldText,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  ),
                  const SizedBox(height: 14),
                  if (_resolving)
                    Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Verifying account…',
                          style: AppTextStyles.body(color: palette.text.withValues(alpha: 0.7), size: 13),
                        ),
                      ],
                    )
                  else if (_resolvedAccountName != null)
                    Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _resolvedAccountName!,
                            style: AppTextStyles.body(color: palette.text, weight: FontWeight.w700, size: 14),
                          ),
                        ),
                      ],
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13)),
                  ],
                  const SizedBox(height: 28),
                  PillButton(
                    label: _saving ? 'Saving…' : 'Save Bank Details',
                    backgroundColor: palette.accent,
                    textColor: palette.onAccent,
                    loading: _saving,
                    onPressed: canSave && !_saving ? _save : null,
                  ),
                ],
              ),
      ),
    );
  }
}

class _BankPickerSheet extends StatefulWidget {
  const _BankPickerSheet({required this.banks, required this.palette});

  final List<Bank> banks;
  final BankDetailsPalette palette;

  @override
  State<_BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<_BankPickerSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.banks
        : widget.banks.where((b) => b.name.toLowerCase().contains(query)).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Select Bank', style: AppTextStyles.heading(color: palette.sheetText, size: 17)),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: AppTextStyles.body(color: palette.sheetText, size: 14),
                decoration: InputDecoration(
                  hintText: 'Search banks',
                  hintStyle: AppTextStyles.body(color: palette.sheetText.withValues(alpha: 0.5), size: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: palette.sheetText.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: palette.sheetSearchFill,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final bank = filtered[index];
                    return ListTile(
                      title: Text(bank.name, style: AppTextStyles.body(color: palette.sheetText)),
                      onTap: () => Navigator.pop(context, bank),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
