import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_exception.dart';
import '../api/models/booking.dart';
import '../api/models/eviction.dart';
import '../core/date_format.dart';
import '../core/theme/app_text_styles.dart';
import '../features/dashboard/models/property.dart';
import '../models/dashboard_theme.dart';
import '../state/app_state.dart';
import 'confirm_sheet.dart';

const _warningRed = Color(0xFFD64545);

/// The tenancy a landlord could ask to end on [property]: a moved-in
/// booking whose lease hasn't finished yet.
Booking? currentTenancyFor(AppState appState, Property property) {
  final now = DateTime.now();
  for (final b in appState.landlordBookings) {
    if (b.property.id != property.id || b.status != BookingStatus.movedIn) continue;
    if (b.leaseEndDate != null && !b.leaseEndDate!.isAfter(now)) continue;
    return b;
  }
  return null;
}

/// Landlord's own property page: the current tenant, plus "Request
/// eviction" (or the request already under review). Drawn on
/// theme.background, so every text uses theme.foreground.
class LandlordEvictionPanel extends StatelessWidget {
  const LandlordEvictionPanel({super.key, required this.property, required this.theme});

  final Property property;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final booking = currentTenancyFor(context.watch<AppState>(), property);
    if (booking == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: LandlordTenancyCard(booking: booking, theme: theme, textColor: theme.foreground, title: booking.tenantName ?? 'Tenant', caption: 'Current tenant'),
    );
  }
}

/// One tenancy on the landlord's side: a caption + title, the lease dates
/// and, while the lease is still running, the eviction controls. [textColor]
/// must contrast with whatever this card sits on (theme.foreground on
/// theme.background, or navy on the off-white tenant profile).
class LandlordTenancyCard extends StatelessWidget {
  const LandlordTenancyCard({
    super.key,
    required this.booking,
    required this.theme,
    required this.textColor,
    required this.title,
    required this.caption,
  });

  final Booking booking;
  final DashboardTheme theme;
  final Color textColor;
  final String title;
  final String caption;

  bool get _isCurrent =>
      booking.status == BookingStatus.movedIn && (booking.leaseEndDate == null || booking.leaseEndDate!.isAfter(DateTime.now()));

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final eviction = appState.evictionForBooking(booking.id);
    final pending = eviction != null && eviction.isPending ? eviction : null;
    final fg = textColor;
    final start = booking.leaseStartDate;
    final end = booking.leaseEndDate;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: AppTextStyles.body(color: fg.withValues(alpha: 0.6), size: 12.5, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(title, style: AppTextStyles.body(color: fg, size: 15, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          _DateLine(label: 'Rented on', value: start == null ? 'Not started yet' : formatShortDate(start), color: fg),
          _DateLine(
            label: _isCurrent ? 'Rent expires' : 'Rent ended',
            value: end == null ? '—' : formatShortDate(end),
            color: fg,
          ),
          // Monthly plan: how far the rent is paid, and a flag once a month
          // is missed (the same pill as an approved eviction).
          if (_isCurrent && booking.payingMonthly && booking.rentPaidThrough != null)
            _DateLine(
              label: booking.hasMonthsLeftToPay ? 'Monthly rent paid until' : 'Monthly rent',
              value: booking.hasMonthsLeftToPay ? formatShortDate(booking.rentPaidThrough!) : 'All months paid',
              color: fg,
            ),
          if (_isCurrent && booking.monthlyRentOverdue) ...[
            const SizedBox(height: 10),
            _StatusPill(
              label: 'Missed monthly rent due ${formatShortDate(booking.rentPaidThrough!)}',
              color: _warningRed,
              textColor: fg,
            ),
          ],
          if (eviction != null && eviction.status == EvictionStatus.approved) ...[
            const SizedBox(height: 10),
            _StatusPill(label: 'Ended by an approved eviction', color: _warningRed, textColor: fg),
          ],
          if (_isCurrent) ...[
            const SizedBox(height: 12),
            if (pending != null) ...[
              _StatusPill(label: 'Eviction request under review', color: const Color(0xFFB7791F), textColor: fg),
              const SizedBox(height: 10),
              _LabeledText(label: 'Your reason', text: pending.reason, color: fg),
              if (pending.tenantResponse != null) ...[
                const SizedBox(height: 8),
                _LabeledText(label: "Tenant's response", text: pending.tenantResponse!, color: fg),
              ],
              const SizedBox(height: 8),
              Text(
                'A HomeServant super admin will review the case. Nothing changes for the tenant unless it is approved.',
                style: AppTextStyles.body(color: fg.withValues(alpha: 0.6), size: 12),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _withdraw(context, pending),
                  child: Text('Withdraw request', style: AppTextStyles.body(color: fg, size: 13, weight: FontWeight.w700)),
                ),
              ),
            ] else ...[
              if (eviction != null && eviction.status == EvictionStatus.rejected) ...[
                _StatusPill(label: 'Last eviction request was rejected', color: _warningRed, textColor: fg),
                if (eviction.reviewNote != null) ...[
                  const SizedBox(height: 8),
                  _LabeledText(label: 'Note from HomeServant', text: eviction.reviewNote!, color: fg),
                ],
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: _warningRed, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: () => showEvictionRequestSheet(context, theme: theme, booking: booking),
                  icon: const Icon(Icons.gavel_rounded, color: _warningRed, size: 18),
                  label: Text('Evict tenant', style: AppTextStyles.button(color: fg, size: 14.5)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, EvictionRequest request) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showConfirmSheet(
      context,
      title: 'Withdraw eviction request?',
      body: 'The tenant will be told you withdrew it. You can file a new one later if needed.',
      actionLabel: 'Withdraw',
    );
    if (!ok) return;
    try {
      await appState.cancelEviction(request.id);
      messenger.showSnackBar(const SnackBar(content: Text('Eviction request withdrawn')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Landlord writes the reason for an eviction; a super admin reviews it.
Future<void> showEvictionRequestSheet(BuildContext context, {required DashboardTheme theme, required Booking booking}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _TextEntrySheet(
      theme: theme,
      title: 'Request eviction',
      intro:
          'Explain why ${booking.tenantName ?? 'this tenant'} should leave ${booking.property.title}. '
          'The tenant is notified and can respond. A HomeServant super admin reviews the case; '
          'the tenancy only ends if they approve it.',
      hint: 'Reason (at least 20 characters)',
      minLength: 20,
      actionLabel: 'Submit for review',
      onSubmit: (text) async {
        await context.read<AppState>().requestEviction(booking.id, text);
        return 'Eviction request sent for review';
      },
    ),
  );
}

/// Tenant's history card: shows a pending eviction request against this
/// booking and lets them respond. Drawn on theme.background.
class TenantEvictionNotice extends StatelessWidget {
  const TenantEvictionNotice({super.key, required this.bookingId, required this.theme});

  final String bookingId;
  final DashboardTheme theme;

  @override
  Widget build(BuildContext context) {
    final eviction = context.watch<AppState>().evictionForBooking(bookingId);
    if (eviction == null || eviction.status == EvictionStatus.cancelled) return const SizedBox.shrink();
    final fg = theme.foreground;
    final pending = eviction.isPending;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _warningRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warningRed.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pending
                ? 'Your landlord has requested to end this tenancy'
                : 'Eviction request ${eviction.status.label.toLowerCase()}',
            style: AppTextStyles.body(color: fg, size: 13.5, weight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _LabeledText(label: "Landlord's reason", text: eviction.reason, color: fg),
          if (eviction.tenantResponse != null) ...[
            const SizedBox(height: 6),
            _LabeledText(label: 'Your response', text: eviction.tenantResponse!, color: fg),
          ],
          if (!pending && eviction.reviewNote != null) ...[
            const SizedBox(height: 6),
            _LabeledText(label: 'Note from HomeServant', text: eviction.reviewNote!, color: fg),
          ],
          const SizedBox(height: 6),
          Text(
            pending
                ? 'Nothing changes unless a HomeServant super admin approves it after reviewing both sides.'
                : eviction.status == EvictionStatus.approved
                ? 'Your lease has ended.'
                : 'Your tenancy continues as normal.',
            style: AppTextStyles.body(color: fg.withValues(alpha: 0.65), size: 12),
          ),
          if (pending)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: theme.surface,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  builder: (_) => _TextEntrySheet(
                    theme: theme,
                    title: 'Your side of the story',
                    intro: 'The super admin reviewing this request will read your response before deciding.',
                    hint: 'Your response',
                    initialText: eviction.tenantResponse,
                    minLength: 5,
                    actionLabel: 'Send response',
                    onSubmit: (text) async {
                      await context.read<AppState>().respondToEviction(eviction.id, text);
                      return 'Response sent';
                    },
                  ),
                ),
                child: Text(
                  eviction.tenantResponse == null ? 'Respond' : 'Edit response',
                  style: AppTextStyles.body(color: fg, size: 13, weight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DateLine extends StatelessWidget {
  const _DateLine({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(width: 96, child: Text(label, style: AppTextStyles.body(color: color.withValues(alpha: 0.6), size: 12.5))),
          Expanded(child: Text(value, style: AppTextStyles.body(color: color, size: 12.5, weight: FontWeight.w600))),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color, required this.textColor});

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: AppTextStyles.body(color: textColor, size: 12, weight: FontWeight.w700)),
    );
  }
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({required this.label, required this.text, required this.color});

  final String label;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body(color: color.withValues(alpha: 0.6), size: 11.5, weight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(text, style: AppTextStyles.body(color: color, size: 13)),
      ],
    );
  }
}

/// Bottom sheet with one multi-line text field, drawn on theme.surface, so
/// everything uses theme.onSurface.
class _TextEntrySheet extends StatefulWidget {
  const _TextEntrySheet({
    required this.theme,
    required this.title,
    required this.intro,
    required this.hint,
    required this.minLength,
    required this.actionLabel,
    required this.onSubmit,
    this.initialText,
  });

  final DashboardTheme theme;
  final String title;
  final String intro;
  final String hint;
  final int minLength;
  final String actionLabel;
  final String? initialText;

  /// Returns the snackbar text on success.
  final Future<String> Function(String text) onSubmit;

  @override
  State<_TextEntrySheet> createState() => _TextEntrySheetState();
}

class _TextEntrySheetState extends State<_TextEntrySheet> {
  late final _controller = TextEditingController(text: widget.initialText ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.length < widget.minLength) {
      setState(() => _error = 'Please write at least ${widget.minLength} characters');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await widget.onSubmit(text);
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final on = theme.onSurface;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: AppTextStyles.heading(color: on, size: 18)),
            const SizedBox(height: 8),
            Text(widget.intro, style: AppTextStyles.body(color: on.withValues(alpha: 0.7), size: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              style: AppTextStyles.body(color: on),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: AppTextStyles.body(color: on.withValues(alpha: 0.45)),
                counterStyle: AppTextStyles.body(color: on.withValues(alpha: 0.5), size: 11),
                errorText: _error,
                errorStyle: AppTextStyles.body(color: _warningRed, size: 12),
                filled: true,
                fillColor: on.withValues(alpha: 0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: theme.onAccent))
                    : Text(widget.actionLabel, style: AppTextStyles.button(color: theme.onAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
