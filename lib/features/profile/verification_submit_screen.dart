import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/verification.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/field_error_text.dart';
import '../../widgets/identification_picker_field.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/upload_picker.dart';
import '../../widgets/upload_picker_rules.dart';
import '../../widgets/verified_badge.dart';

/// Dark red on the off-white page (about 6:1).
const _errorColor = Color(0xFFA61B1B);

/// "Get verified" after signup — for accounts created before ID documents
/// were required, or to resubmit after a rejection. Same fields and rules
/// as signup: means of ID + number for everyone; landlords also upload a
/// certificate of ownership and a supporting document (photo or PDF).
/// Off-white page, navy text.
class VerificationSubmitScreen extends StatefulWidget {
  const VerificationSubmitScreen({super.key});

  @override
  State<VerificationSubmitScreen> createState() => _VerificationSubmitScreenState();
}

class _VerificationSubmitScreenState extends State<VerificationSubmitScreen> {
  final _idKey = GlobalKey<IdentificationPickerFieldState>();
  PickedUpload? _certificate;
  PickedUpload? _document;
  String? _certificateError;
  String? _documentError;
  String? _error;
  bool _submitting = false;

  bool get _isLandlord => context.read<AppState>().role == UserRole.landlord;

  Future<void> _pick(bool certificate) async {
    final picked = await pickUpload(context);
    if (picked == null) return;
    setState(() {
      if (certificate) {
        _certificate = picked;
        _certificateError = null;
      } else {
        _document = picked;
        _documentError = null;
      }
    });
  }

  String? _fileError(PickedUpload? file, String missing) {
    if (file == null) return missing;
    return isPhotoOrPdf(file) ? null : 'Upload a photo or a PDF';
  }

  Future<void> _submit() async {
    final idValid = _idKey.currentState?.validate() ?? false;
    final certificateError = _isLandlord ? _fileError(_certificate, 'Upload your certificate of ownership') : null;
    final documentError = _isLandlord ? _fileError(_document, 'Upload your supporting document') : null;
    setState(() {
      _certificateError = certificateError;
      _documentError = documentError;
      _error = null;
    });
    if (!idValid || certificateError != null || documentError != null) return;

    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    try {
      final id = _idKey.currentState!;
      String? certificatePath;
      String? documentPath;
      if (_isLandlord) {
        certificatePath = await appState.uploads.uploadPrivateDocument(_certificate!);
        documentPath = await appState.uploads.uploadPrivateDocument(_document!);
      }
      // The server checks the ID number with the body that issued it, so
      // this can come back already verified rather than pending.
      final status = await appState.verification.update(
        idType: id.selectedType,
        idNumber: id.number,
        certificatePath: certificatePath,
        documentPath: documentPath,
      );
      await appState.refreshProfile();
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            status == VerificationStatus.approved
                ? "You're verified — we confirmed your ID with the body that issued it."
                : "Documents sent. We'll let you know once you're verified.",
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final landlord = appState.role == UserRole.landlord;
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Get Verified', style: AppTextStyles.heading(color: Colors.white, size: 18)),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                VerificationStatusCard(
                  status: appState.verificationStatus,
                  note: appState.verificationNote,
                  listingsHidden: appState.listingsHiddenUntilVerified,
                ),
                const SizedBox(height: 18),
                Text(
                  landlord
                      ? 'Give your means of ID and upload your certificate of ownership and a supporting document (a photo or a PDF). '
                            'They are stored privately and only HomeServant reviewers can see them. Your ID number is checked '
                            'with the body that issued it; your ownership documents are then reviewed by a person.'
                      : 'Give your means of ID. It is stored privately and only HomeServant reviewers can see it. We check the '
                            'number with the body that issued it, so this is usually instant — make sure the name on your '
                            'profile matches the name on your ID.',
                  style: AppTextStyles.body(color: AppColors.navy.withValues(alpha: 0.8), size: 13.5),
                ),
                const SizedBox(height: 18),
                IdentificationPickerField(key: _idKey, labelColor: AppColors.navy, errorColor: _errorColor),
                if (landlord) ...[
                  const SizedBox(height: 22),
                  Text('Certificate of Ownership', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  PillOutlineButton(
                    label: _certificate?.fileName ?? 'Upload certificate',
                    textColor: AppColors.navy,
                    icon: Icons.upload_file_rounded,
                    onPressed: () => _pick(true),
                  ),
                  FieldErrorText(_certificateError, color: _errorColor),
                  const SizedBox(height: 18),
                  Text('Supporting Document', style: AppTextStyles.body(color: AppColors.navy, weight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  PillOutlineButton(
                    label: _document?.fileName ?? 'Upload document',
                    textColor: AppColors.navy,
                    icon: Icons.upload_file_rounded,
                    onPressed: () => _pick(false),
                  ),
                  FieldErrorText(_documentError, color: _errorColor),
                ],
                FieldErrorText(_error, color: _errorColor, textAlign: TextAlign.center),
                const SizedBox(height: 28),
                PillButton(
                  label: _submitting ? 'Sending…' : 'Submit for review',
                  backgroundColor: AppColors.navy,
                  textColor: Colors.white,
                  loading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether this account can (re)submit documents now: nothing submitted,
/// unfinished, or rejected. Not while in review or once verified.
bool canSubmitVerification(VerificationStatus? status) =>
    status == null || status == VerificationStatus.incomplete || status == VerificationStatus.rejected;
