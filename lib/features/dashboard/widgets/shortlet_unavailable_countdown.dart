import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_text_styles.dart';

/// A simple ticking "Unavailable — back in Xh Ym" label shown in place of
/// the normal booking CTA while a Shortlet is currently booked out.
/// Re-renders every minute — no need for anything more elaborate than a
/// plain countdown `Text`.
class ShortletUnavailableCountdown extends StatefulWidget {
  const ShortletUnavailableCountdown({super.key, required this.until, required this.color, this.size = 13});

  final DateTime until;
  final Color color;
  final double size;

  @override
  State<ShortletUnavailableCountdown> createState() => _ShortletUnavailableCountdownState();
}

class _ShortletUnavailableCountdownState extends State<ShortletUnavailableCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.until.difference(DateTime.now());
    final label = remaining.isNegative
        ? 'Unavailable'
        : 'Unavailable · back in ${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
    return Text(label, style: AppTextStyles.body(color: widget.color, size: widget.size, weight: FontWeight.w700));
  }
}
