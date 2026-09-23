import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/bank.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';

/// Lets a landlord set the bank account tenant payments get credited to.
/// The account number is resolved against Paystack as soon as a bank is
/// picked and 10 digits are entered, so the landlord sees and confirms
/// the real account holder's name before saving — the same name the
/// server independently re-resolves and actually persists.
class LandlordBankDetailsScreen extends StatefulWidget {
  const LandlordBankDetailsScreen({super.key});

  @override
  State<LandlordBankDetailsScreen> createState() => _LandlordBankDetailsScreenState();
}

class _LandlordBankDetailsScreenState extends State<LandlordBankDetailsScreen> {
  final _accountNumber = TextEditingController();
  List<Bank>? _banks;
  Bank? _selectedBank;
  String? _resolvedAccountName;
  bool _resolving = false;
  bool _saving = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _accountNumber.text = appState.accountNumber ?? '';
    _resolvedAccountName = appState.accountName;
    _loadBanks(preselectCode: appState.bankCode);
    _accountNumber.addListener(_onAccountNumberChanged);
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
    final result = await showModalBottomSheet<Bank>(
      context: context,
      backgroundColor: AppColors.navyDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => _BankPickerSheet(banks: banks),
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
      await context.read<AppState>().updateBankDetails(
        bankCode: bank.code,
        accountNumber: _accountNumber.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bank details saved')));
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _selectedBank != null && _resolvedAccountName != null && !_resolving;
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
        title: Text('Bank Details', style: AppTextStyles.heading(color: AppColors.gold, size: 18)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                "This is the account that will be credited whenever a tenant pays you. Double-check the "
                'account holder name below matches yours before saving.',
                style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.85), size: 13),
              ),
            ),
            const SizedBox(height: 24),
            Text('Bank', style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w600, size: 13.5)),
            const SizedBox(height: 8),
            InkWell(
              onTap: _banks == null ? null : _pickBank,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        _selectedBank?.name ?? (_banks == null ? 'Loading banks…' : 'Select your bank'),
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.body(color: AppColors.navy, size: 15),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.inputFieldGrey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Account Number', style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w600, size: 13.5)),
            const SizedBox(height: 8),
            PillTextField(
              hint: '10-digit account number',
              controller: _accountNumber,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            ),
            const SizedBox(height: 14),
            if (_resolving)
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                  ),
                  const SizedBox(width: 10),
                  Text('Verifying account…', style: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.7), size: 13)),
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
                      style: AppTextStyles.body(color: Colors.white, weight: FontWeight.w700, size: 14),
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
              backgroundColor: AppColors.gold,
              textColor: AppColors.navy,
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
  const _BankPickerSheet({required this.banks});

  final List<Bank> banks;

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
              Text('Select Bank', style: AppTextStyles.heading(color: Colors.white, size: 17)),
              const SizedBox(height: 14),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: AppTextStyles.body(color: Colors.white, size: 14),
                decoration: InputDecoration(
                  hintText: 'Search banks',
                  hintStyle: AppTextStyles.body(color: Colors.white.withValues(alpha: 0.5), size: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.5)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.08),
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
                      title: Text(bank.name, style: AppTextStyles.body(color: Colors.white)),
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
