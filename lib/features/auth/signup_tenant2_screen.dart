import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/user_role.dart';
import '../../state/app_state.dart';
import '../../widgets/home_servant_logo.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/themed_scaffold.dart';
import '../../widgets/upload_picker.dart';

class SignupTenant2Screen extends StatefulWidget {
  const SignupTenant2Screen({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<SignupTenant2Screen> createState() => _SignupTenant2ScreenState();
}

class _SignupTenant2ScreenState extends State<SignupTenant2Screen> {
  static const _idOptions = ['NIN', "Driver's License", "Voter's Card", 'International Passport'];
  static const _role = UserRole.tenant;

  final _addressController = TextEditingController();
  final _idNumberController = TextEditingController();
  String? _identification;
  PickedUpload? _photo;
  bool _submitting = false;
  String? _error;

  /// Means-of-identification isn't persisted anywhere yet — the backend has
  /// no KYC/verification model, so it's collected here for UI completeness
  /// but only the photo and address actually save.
  Future<void> _finish() async {
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
      await appState.completeProfile(houseAddress: _addressController.text.trim(), profilePhotoUrl: photoUrl);
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
    _addressController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await pickUpload(context);
    if (picked != null) {
      setState(() => _photo = picked);
    }
  }

  Future<void> _pickIdentification() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _idOptions
              .map((option) => ListTile(
                    title: Text(option, style: AppTextStyles.body(color: AppColors.navy)),
                    trailing: option == _identification ? const Icon(Icons.check, color: AppColors.gold) : null,
                    onTap: () => Navigator.pop(context, option),
                  ))
              .toList(),
        ),
      ),
    );
    if (result != null && result != _identification) {
      setState(() {
        _identification = result;
        _idNumberController.clear();
      });
    }
  }

  // Standard Nigerian ID number formats, keyed by the option label in
  // _idOptions, so the number field only accepts/shapes input the way
  // each issuing body actually formats it.
  ({String hint, int maxLength, bool numeric})? get _idNumberFormat {
    switch (_identification) {
      case 'NIN':
        return (hint: 'Enter your 11-digit NIN', maxLength: 11, numeric: true);
      case "Driver's License":
        return (hint: 'e.g. ABC12345D12', maxLength: 12, numeric: false);
      case "Voter's Card":
        return (hint: "Enter your 19-character Voter's Card (VIN) number", maxLength: 19, numeric: false);
      case 'International Passport':
        return (hint: 'e.g. A12345678', maxLength: 9, numeric: false);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    const panelColor = Color(0xFF1B3255);
    return ThemedScaffold(
      role: _role,
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
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: _role.accent.withValues(alpha: 0.3),
                    backgroundImage: _photo != null && _photo!.isImage ? _photo!.imageProvider : null,
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
          Text("What's your address?", style: AppTextStyles.body(color: _role.foreground, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          PillTextField(
            hint: 'Enter your address',
            controller: _addressController,
            minLines: 3,
            maxLines: 5,
            borderRadius: 20,
          ),
          const SizedBox(height: 22),
          LabeledDropdownField(
            label: 'Means of Identification',
            value: _identification ?? 'Select your means of identification',
            labelColor: _role.foreground,
            onTap: _pickIdentification,
          ),
          if (_idNumberFormat case final format?) ...[
            const SizedBox(height: 14),
            PillTextField(
              hint: format.hint,
              controller: _idNumberController,
              keyboardType: format.numeric ? TextInputType.number : TextInputType.text,
              inputFormatters: [
                if (format.numeric)
                  FilteringTextInputFormatter.digitsOnly
                else ...[
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
                  ),
                ],
                LengthLimitingTextInputFormatter(format.maxLength),
              ],
            ),
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
    );
  }
}
