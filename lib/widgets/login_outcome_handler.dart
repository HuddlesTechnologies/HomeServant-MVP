import 'package:flutter/material.dart';
import '../state/app_state.dart';
import 'reactivate_account_dialog.dart';

/// Shared handling for the [LoginOutcome] returned by `AppState.login`/
/// `loginWithGoogle` — every login/signup screen in the app switches over
/// the same three cases with the same reactivation-confirmation dance, so
/// this factors that out.
///
/// [onReactivate] is the retry to run (e.g. re-calling the same login with
/// `reactivate: true`) once the user confirms via
/// [showReactivateAccountDialog]; it's only invoked if the dialog is still
/// mounted-relevant when it resolves.
Future<void> handleLoginOutcome(
  BuildContext context,
  LoginOutcome outcome, {
  required VoidCallback onSuccess,
  required VoidCallback onTwoFactor,
  required Future<void> Function() onReactivate,
}) async {
  switch (outcome) {
    case LoginOutcome.success:
      onSuccess();
    case LoginOutcome.requiresTwoFactor:
      onTwoFactor();
    case LoginOutcome.requiresReactivation:
      final confirmed = await showReactivateAccountDialog(context);
      if (confirmed == true && context.mounted) await onReactivate();
  }
}
