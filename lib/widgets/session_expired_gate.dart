import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../state/app_state.dart';
import 'pill_button.dart';

/// Wraps the whole app (via `MaterialApp.builder`, alongside [AppLockGate])
/// and shows a properly styled modal over everything whenever
/// [AppState.sessionExpired] flips true — a refresh-token failure meant
/// the session genuinely expired, not just an access token due for
/// renewal (see ApiClient.onSessionExpired). Without this, a session
/// timing out mid-use just silently cleared local state with no
/// explanation, leaving whatever screen was open in a broken
/// logged-out-but-still-rendered state.
class SessionExpiredGate extends StatelessWidget {
  const SessionExpiredGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final expired = context.watch<AppState>().sessionExpired;
    return Stack(
      children: [
        child,
        if (expired) _SessionExpiredModal(
          onLogInAgain: () {
            context.read<AppState>().acknowledgeSessionExpired();
            context.go('/get-started');
          },
        ),
      ],
    );
  }
}

class _SessionExpiredModal extends StatelessWidget {
  const _SessionExpiredModal({required this.onLogInAgain});

  final VoidCallback onLogInAgain;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          constraints: const BoxConstraints(maxWidth: 380),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 12))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.lock_clock_rounded, color: AppColors.navy, size: 32),
              ),
              const SizedBox(height: 20),
              Text(
                'Session Expired',
                textAlign: TextAlign.center,
                style: AppTextStyles.heading(color: AppColors.navy, size: 19),
              ),
              const SizedBox(height: 10),
              Text(
                "For your security, you've been signed out. Please log in again to continue.",
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.7), size: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: PillButton(
                  label: 'Log In Again',
                  backgroundColor: AppColors.navy,
                  textColor: Colors.white,
                  onPressed: onLogInAgain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
