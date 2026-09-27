import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_exception.dart';
import '../core/theme/app_text_styles.dart';
import '../models/dashboard_theme.dart';
import '../state/app_state.dart';

/// Asks the customer to rate a resolved support conversation (1–5 stars,
/// optional comment) — feeds the admins' Support Insights dashboard.
/// Drawn on theme.surface with theme.onSurface text/icons (a fixed pair in
/// every theme); filled vs outlined stars carry the choice, not colour.
class SupportRatingCard extends StatefulWidget {
  const SupportRatingCard({super.key, required this.theme, required this.threadId, this.onRated});

  final DashboardTheme theme;
  final String threadId;
  final VoidCallback? onRated;

  @override
  State<SupportRatingCard> createState() => _SupportRatingCardState();
}

class _SupportRatingCardState extends State<SupportRatingCard> {
  int _rating = 0;
  bool _sending = false;
  bool _done = false;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AppState>().chat.rateSupportThread(widget.threadId, _rating, comment: _comment.text);
      if (!mounted) return;
      setState(() => _done = true);
      widget.onRated?.call();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: theme.surface, borderRadius: BorderRadius.circular(16)),
      child: _done
          ? Text('Thanks for your feedback!', style: AppTextStyles.body(color: theme.onSurface, size: 14, weight: FontWeight.w700))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How did we do?', style: AppTextStyles.heading(color: theme.onSurface, size: 16)),
                const SizedBox(height: 4),
                Text(
                  'Rate this support conversation.',
                  style: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.65), size: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var star = 1; star <= 5; star++)
                      IconButton(
                        onPressed: () => setState(() => _rating = star),
                        tooltip: '$star of 5',
                        icon: Icon(
                          star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: theme.onSurface,
                          size: 30,
                        ),
                      ),
                  ],
                ),
                if (_rating > 0) ...[
                  TextField(
                    controller: _comment,
                    minLines: 1,
                    maxLines: 4,
                    style: AppTextStyles.body(color: theme.onSurface, size: 14),
                    cursorColor: theme.onSurface,
                    decoration: InputDecoration(
                      hintText: 'Anything to add? (optional)',
                      hintStyle: AppTextStyles.body(color: theme.onSurface.withValues(alpha: 0.45), size: 14),
                      filled: true,
                      fillColor: theme.onSurface.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: _sending ? null : _submit,
                      child: Text(
                        _sending ? 'Sending…' : 'Send rating',
                        style: AppTextStyles.body(color: theme.onAccent, weight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
