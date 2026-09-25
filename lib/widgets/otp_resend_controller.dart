import 'dart:async';
import 'package:flutter/material.dart';

/// Owns the resend-countdown state shared by every OTP/reset-code screen:
/// a [Timer.periodic] counting down from [startSeconds], plus the busy
/// flag while a resend request is in flight. The countdown label and
/// "Resend ..." button wording differ per screen, so [builder] is handed
/// the current `secondsLeft`/`resending` values and a ready-to-use
/// `onPressed` callback (already `null` while the timer is still running
/// or a resend is in flight) and renders whatever markup that screen
/// needs around them.
class OtpResendController extends StatefulWidget {
  const OtpResendController({
    super.key,
    this.startSeconds = 50,
    this.onResend,
    required this.builder,
  });

  final int startSeconds;

  /// Performs the actual resend request. Return `true` to restart the
  /// countdown (a successful resend) or `false` to leave it at zero (the
  /// caller is expected to have already recorded whatever error it wants
  /// shown). Omit entirely for a "resend" that's just a local countdown
  /// restart with no request behind it.
  final Future<bool> Function()? onResend;

  final Widget Function(
    BuildContext context,
    int secondsLeft,
    bool resending,
    VoidCallback? onResendPressed,
  ) builder;

  @override
  State<OtpResendController> createState() => _OtpResendControllerState();
}

class _OtpResendControllerState extends State<OtpResendController> {
  late int _secondsLeft = widget.startSeconds;
  Timer? _timer;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = widget.startSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  Future<void> _handleResend() async {
    final onResend = widget.onResend;
    if (onResend == null) {
      _startTimer();
      return;
    }
    setState(() => _resending = true);
    try {
      final shouldRestart = await onResend();
      if (!mounted) return;
      if (shouldRestart) _startTimer();
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = _secondsLeft == 0 && !_resending ? _handleResend : null;
    return widget.builder(context, _secondsLeft, _resending, onPressed);
  }
}
