import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Drag down to refresh, with the spinner's colours chosen explicitly:
/// [color] on a [backgroundColor] disc (navy on white by default, which
/// reads over every screen since the disc brings its own background).
///
/// The [child] scrollable should use [alwaysScrollable] physics so a list
/// shorter than the screen can still be pulled.
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.color = AppColors.navy,
    this.backgroundColor = AppColors.white,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final Color color;
  final Color backgroundColor;

  /// Physics for the wrapped list: scrollable (and so pullable) even when
  /// its content fits on screen.
  static const alwaysScrollable = AlwaysScrollableScrollPhysics();

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: onRefresh, color: color, backgroundColor: backgroundColor, child: child);
  }
}

/// A centred message (an empty state) that can still be pulled to refresh —
/// a plain [Center] isn't scrollable, so [RefreshIndicator] never sees the
/// drag.
class PullableEmptyState extends StatelessWidget {
  const PullableEmptyState({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: PullToRefresh.alwaysScrollable,
        children: [
          SizedBox(height: constraints.maxHeight, child: Center(child: child)),
        ],
      ),
    );
  }
}
