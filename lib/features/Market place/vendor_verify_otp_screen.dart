import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/vendor.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/otp_input_row.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/upload_picker.dart';
import 'vendor_signup_success_screen.dart';

/// Verifies the signup email code, then creates the vendor's shop profile
/// with everything collected on [VendorSignupScreen] — the account only
/// gets tokens (and can only call `POST /vendors/me`) once verified, so
/// this step has to come between signup and having a real shop.
class VendorVerifyOtpScreen extends StatefulWidget {
  const VendorVerifyOtpScreen({
    super.key,
    required this.theme,
    required this.email,
    required this.businessName,
    required this.category,
    required this.state,
    required this.rcNumber,
    required this.phone,
    this.logo,
  });

  final DashboardTheme theme;
  final String email;
  final String businessName;
  final MarketplaceCategory category;
  final String state;
  final String rcNumber;
  final String phone;
  final PickedUpload? logo;

  @override
  State<VendorVerifyOtpScreen> createState() => _VendorVerifyOtpScreenState();
}

class _VendorVerifyOtpScreenState extends State<VendorVerifyOtpScreen> {
  static const _startSeconds = 50;
  int _secondsLeft = _startSeconds;
  Timer? _timer;
  String _code = '';
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _startSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 0) {
        timer.cancel();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final appState = context.read<AppState>();
    try {
      await appState.verifySignupOtp(_code);

      String? logoUrl;
      final logo = widget.logo;
      if (logo != null && logo.isImage) {
        logoUrl = await appState.uploads.upload(file: logo, folder: 'vendor-logos');
      }

      await appState.vendors.create(
        businessName: widget.businessName,
        category: widget.category,
        state: widget.state,
        rcNumber: widget.rcNumber.isEmpty ? null : widget.rcNumber,
        logoUrl: logoUrl,
      );
      await appState.completeProfile(phoneNumber: widget.phone);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VendorSignupSuccessScreen(theme: widget.theme, businessName: widget.businessName),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Text('Verify Your Email', textAlign: TextAlign.center, style: AppTextStyles.heading(color: theme.foreground, size: 26)),
              const SizedBox(height: 8),
              Text(
                'Enter the code sent to ${widget.email}',
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.65), size: 14.5),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Enter OTP', style: AppTextStyles.body(color: theme.foreground, weight: FontWeight.w600)),
                  Text(
                    '0:${_secondsLeft.toString().padLeft(2, '0')}',
                    style: AppTextStyles.body(color: theme.foreground.withValues(alpha: 0.6), size: 13),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OtpInputRow(
                boxColor: theme.surface,
                textColor: theme.onSurface,
                onChanged: (value) => setState(() => _code = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              PillButton(
                label: _submitting ? 'Verifying…' : 'Continue',
                backgroundColor: theme.accent,
                textColor: theme.onAccent,
                loading: _submitting,
                onPressed: _code.length == 4 && !_submitting ? _submit : null,
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _secondsLeft == 0 ? _startTimer : null,
                  child: Text(
                    _secondsLeft == 0 ? 'Resend OTP' : 'Resend available after timer ends',
                    style: AppTextStyles.body(
                      color: _secondsLeft == 0 ? theme.accent : theme.foreground.withValues(alpha: 0.4),
                      weight: FontWeight.w600,
                      size: 13,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
