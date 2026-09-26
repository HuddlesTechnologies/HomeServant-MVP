import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/auth_user.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/home_servant_logo.dart';
import '../../widgets/identification_picker_field.dart';
import '../../widgets/labeled_pill_field.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/themed_scaffold.dart';
import '../../widgets/upload_picker.dart';

class SignupLandlord2Screen extends StatefulWidget {
  const SignupLandlord2Screen({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<SignupLandlord2Screen> createState() => _SignupLandlord2ScreenState();
}

class _SignupLandlord2ScreenState extends State<SignupLandlord2Screen> {
  static const _role = UserRole.landlord;

  final _formKey = GlobalKey<FormState>();
  final _occupationController = TextEditingController();
  PickedUpload? _document;
  PickedUpload? _photo;
  Gender? _gender;
  MaritalStatus? _maritalStatus;
  bool _showGenderError = false;
  bool _showMaritalStatusError = false;
  bool _submitting = false;
  String? _error;

  /// The verification document/ID number aren't persisted anywhere yet —
  /// the backend has no KYC model, so they're collected here for UI
  /// completeness but only the profile photo and the fields below actually
  /// save.
  Future<void> _finish() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    final missingGender = _gender == null;
    final missingMaritalStatus = _maritalStatus == null;
    if (!formValid || missingGender || missingMaritalStatus) {
      setState(() {
        _showGenderError = missingGender;
        _showMaritalStatusError = missingMaritalStatus;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final appState = context.read<AppState>();
    try {
      final photo = _photo;
      String? photoUrl;
      if (photo != null && photo.isImage) {
        photoUrl = await appState.uploads.upload(file: photo, folder: 'profile-photos');
      }
      await appState.completeProfile(
        profilePhotoUrl: photoUrl,
        gender: _gender,
        occupation: _occupationController.text.trim(),
        maritalStatus: _maritalStatus,
      );
      if (!mounted) return;
      widget.onFinish();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _occupationController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await pickUpload(context);
    if (picked != null) {
      setState(() => _photo = picked);
    }
  }

  Future<void> _pickDocument() async {
    final picked = await pickUpload(context);
    if (picked != null) {
      setState(() => _document = picked);
    }
  }

  Future<void> _pickMaritalStatus() async {
    final result = await showModalBottomSheet<MaritalStatus>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: MaritalStatus.values
              .map((option) => ListTile(
                    title: Text(option.label, style: AppTextStyles.body(color: AppColors.navy)),
                    trailing: option == _maritalStatus ? const Icon(Icons.check, color: AppColors.gold) : null,
                    onTap: () => Navigator.pop(context, option),
                  ))
              .toList(),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _maritalStatus = result;
        _showMaritalStatusError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const panelColor = AppColors.offWhite;
    return ThemedScaffold(
      role: _role,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(child: HomeServantLogo(role: _role, iconSize: 56)),
            const SizedBox(height: 36),
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(color: panelColor, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _role.accent.withValues(alpha: 0.3),
                        // Biased toward the top rather than dead-center — a plain
                        // center-crop on an uncropped photo tends to zoom in on
                        // the nose/mouth instead of showing the whole face.
                        image: _photo != null && _photo!.isImage
                            ? DecorationImage(image: _photo!.imageProvider, fit: BoxFit.contain)
                            : null,
                      ),
                      child: _photo == null
                          ? Icon(Icons.person, size: 40, color: _role.foreground)
                          : (_photo!.isImage ? null : Icon(Icons.insert_drive_file_rounded, size: 32, color: _role.foreground)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _photo?.fileName ?? 'Add a Photo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.body(color: _role.accent, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            PillOutlineButton(
              label: _document?.fileName ?? 'Upload your document',
              textColor: AppColors.navy,
              icon: Icons.upload_file_rounded,
              onPressed: _pickDocument,
            ),
            const SizedBox(height: 22),
            IdentificationPickerField(labelColor: _role.foreground),
            const SizedBox(height: 22),
            Text('Gender', style: AppTextStyles.body(color: _role.foreground, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final option in Gender.values) ...[
                  if (option != Gender.values.first) const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _gender = option;
                        _showGenderError = false;
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _gender == option ? _role.accent : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          option.label,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body(
                            color: _gender == option ? Colors.white : AppColors.navy,
                            weight: FontWeight.w600,
                            size: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_showGenderError) ...[
              const SizedBox(height: 6),
              Text('Please select your gender', style: AppTextStyles.body(color: Colors.redAccent, size: 12)),
            ],
            const SizedBox(height: 22),
            LabeledPillField(
              label: 'Occupation',
              labelColor: _role.foreground,
              controller: _occupationController,
              hint: 'Enter your occupation',
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Enter your occupation';
                return null;
              },
            ),
            const SizedBox(height: 22),
            LabeledDropdownField(
              label: 'Marital Status',
              value: _maritalStatus?.label ?? 'Select your marital status',
              labelColor: _role.foreground,
              onTap: _pickMaritalStatus,
            ),
            if (_showMaritalStatusError) ...[
              const SizedBox(height: 6),
              Text('Please select your marital status', style: AppTextStyles.body(color: Colors.redAccent, size: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppTextStyles.body(color: Colors.redAccent, size: 13), textAlign: TextAlign.center),
            ],
            const SizedBox(height: 32),
            PillButton(
              label: _submitting ? 'Saving…' : 'Continue',
              backgroundColor: _role.accent,
              textColor: Colors.white,
              loading: _submitting,
              onPressed: _submitting ? null : _finish,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
