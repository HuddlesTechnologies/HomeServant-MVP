import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../../api/models/tenancy_agreement.dart';
import '../../../core/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../models/dashboard_theme.dart';
import '../../../state/app_state.dart';
import '../../../widgets/dashboard_page_scaffold.dart';
import 'tenancy_agreement_content.dart';
import 'tenancy_agreement_pdf.dart';

/// Fetches and renders the real, persisted `TenancyAgreement` for
/// [bookingId] (`GET /bookings/:id/tenancy-agreement`) — generated
/// server-side on move-in. No client-side fabrication: if the backend
/// hasn't generated one yet (booking not yet moved in), this shows an
/// explicit "not ready" state instead of inventing one.
class TenancyAgreementViewScreen extends StatefulWidget {
  const TenancyAgreementViewScreen({super.key, required this.theme, required this.bookingId});

  final DashboardTheme theme;
  final String bookingId;

  @override
  State<TenancyAgreementViewScreen> createState() => _TenancyAgreementViewScreenState();
}

class _TenancyAgreementViewScreenState extends State<TenancyAgreementViewScreen> {
  bool _loading = true;
  bool _downloading = false;
  TenancyAgreement? _agreement;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final agreement = await context.read<AppState>().fetchTenancyAgreement(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _agreement = agreement;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _download(TenancyAgreementContent content) async {
    setState(() => _downloading = true);
    try {
      final doc = await buildTenancyAgreementPdf(content);
      final bytes = await doc.save();
      final fileSlug = content.propertyTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      await Printing.sharePdf(bytes: bytes, filename: 'tenancy_agreement_$fileSlug.pdf');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final agreement = _agreement;

    return DashboardPageScaffold(
      background: theme.background,
      foreground: theme.foreground,
      title: 'Tenancy Agreement',
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : agreement == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "This tenancy agreement isn't ready yet — it's generated automatically once move-in is "
                    'confirmed.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.7), size: 14),
                  ),
                ),
              )
            : ResponsiveCenter(
                maxWidth: 720,
                child: Builder(
                  builder: (context) {
                    final content = buildTenancyAgreementContent(agreement);
                    return Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            children: [_DocumentPaper(theme: theme, content: content)],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _downloading ? null : () => _download(content),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.accent,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                              ),
                              icon: _downloading
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: theme.onAccent),
                                    )
                                  : Icon(Icons.download_rounded, color: theme.onAccent, size: 20),
                              label: Text(
                                _downloading ? 'Preparing PDF…' : 'Download PDF',
                                style: AppTextStyles.button(color: theme.onAccent),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}

/// A paper-like card presenting the filled MOU — separate from the app's
/// surrounding theme colours since a legal document reads better as a fixed
/// navy-on-white sheet than one that shifts with the tenant's chosen theme.
class _DocumentPaper extends StatelessWidget {
  const _DocumentPaper({required this.theme, required this.content});

  final DashboardTheme theme;
  final TenancyAgreementContent content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.navy.withValues(alpha: 0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              TenancyAgreementContent.documentTitle.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTextStyles.heading(color: AppColors.navy, size: 17),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              TenancyAgreementContent.documentSubtitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.55), size: 12),
            ),
          ),
          const SizedBox(height: 20),
          Text(content.madeOnLine, style: AppTextStyles.body(color: AppColors.navy, size: 13)),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _PartyBlock(label: 'LANDLORD', party: content.landlord)),
              const SizedBox(width: 20),
              Expanded(child: _PartyBlock(label: 'TENANT', party: content.tenant)),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: AppColors.navy.withValues(alpha: 0.1)),
          const SizedBox(height: 8),
          for (final clause in content.clauses)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${clause.number}. ${clause.title}',
                    style: AppTextStyles.body(color: AppColors.navy, size: 13.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    clause.body,
                    style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.78), size: 13).copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'SIGNED / ACCEPTED BY THE PARTIES',
            style: AppTextStyles.body(color: AppColors.navy, size: 13.5, weight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _SignatureBlock(label: 'LANDLORD', name: content.landlord.name)),
              const SizedBox(width: 20),
              Expanded(child: _SignatureBlock(label: 'TENANT', name: content.tenant.name)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _SignatureBlock(label: 'WITNESS 1', name: null)),
              const SizedBox(width: 20),
              Expanded(child: _SignatureBlock(label: 'WITNESS 2', name: null)),
            ],
          ),
          const SizedBox(height: 24),
          Divider(color: AppColors.navy.withValues(alpha: 0.1)),
          const SizedBox(height: 10),
          Text(content.generatedNote, style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.5), size: 11)),
          const SizedBox(height: 6),
          Text(content.disclaimer, style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.5), size: 11)),
        ],
      ),
    );
  }
}

class _PartyBlock extends StatelessWidget {
  const _PartyBlock({required this.label, required this.party});

  final String label;
  final TenancyParty party;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body(color: AppColors.goldDark, size: 10.5, weight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(party.name, style: AppTextStyles.body(color: AppColors.navy, size: 13, weight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('Address: ${party.address}', style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.6), size: 11.5)),
        Text('Phone: ${party.phone}', style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.6), size: 11.5)),
        Text('Email: ${party.email}', style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.6), size: 11.5)),
      ],
    );
  }
}

class _SignatureBlock extends StatelessWidget {
  const _SignatureBlock({required this.label, required this.name});

  final String label;
  final String? name;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body(color: AppColors.navy, size: 11, weight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text('Name: ${name ?? '_______________'}', style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.7), size: 11.5)),
        const SizedBox(height: 18),
        Container(height: 1, color: AppColors.navy.withValues(alpha: 0.2)),
        const SizedBox(height: 4),
        Text('Signature', style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.45), size: 10)),
        const SizedBox(height: 14),
        Container(height: 1, color: AppColors.navy.withValues(alpha: 0.2)),
        const SizedBox(height: 4),
        Text('Date', style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.45), size: 10)),
      ],
    );
  }
}
