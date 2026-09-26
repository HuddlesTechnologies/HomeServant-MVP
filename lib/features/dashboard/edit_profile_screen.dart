import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../api/api_exception.dart';
import '../../api/models/auth_user.dart';
import '../../core/date_format.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../models/dashboard_theme.dart';
import '../../state/app_state.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_text_field.dart';
import '../../widgets/upload_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullName;
  late final TextEditingController _dob;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _gender;
  late final TextEditingController _occupation;
  late final TextEditingController _maritalStatus;
  final _fullNameFocus = FocusNode();
  final _addressFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _occupationFocus = FocusNode();
  DateTime? _dateOfBirth;
  String? _photoPath;
  Gender? _genderValue;
  MaritalStatus? _maritalStatusValue;
  bool _saving = false;

  bool _fullNameEditable = false;
  bool _dobEditable = false;
  bool _addressEditable = false;
  bool _phoneEditable = false;
  bool _genderEditable = false;
  bool _occupationEditable = false;
  bool _maritalStatusEditable = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    // Real values only — an empty field here means the account genuinely
    // has nothing saved yet, not a placeholder pretending it does.
    _fullName = TextEditingController(text: appState.fullName);
    _dateOfBirth = appState.dateOfBirth;
    _dob = TextEditingController(text: _dateOfBirth != null ? formatShortDate(_dateOfBirth!) : '');
    _address = TextEditingController(text: appState.houseAddress);
    _phone = TextEditingController(text: appState.phoneNumber);
    _photoPath = appState.profilePhotoPath;
    _genderValue = appState.gender;
    _gender = TextEditingController(text: _genderValue?.label ?? '');
    _occupation = TextEditingController(text: appState.occupation ?? '');
    _maritalStatusValue = appState.maritalStatus;
    _maritalStatus = TextEditingController(text: _maritalStatusValue?.label ?? '');
  }

  @override
  void dispose() {
    _fullName.dispose();
    _dob.dispose();
    _address.dispose();
    _phone.dispose();
    _gender.dispose();
    _occupation.dispose();
    _maritalStatus.dispose();
    _fullNameFocus.dispose();
    _addressFocus.dispose();
    _phoneFocus.dispose();
    _occupationFocus.dispose();
    super.dispose();
  }

  Future<void> _pickGender() async {
    final result = await showModalBottomSheet<Gender>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: Gender.values
              .map((option) => ListTile(
                    title: Text(option.label, style: AppTextStyles.body(color: AppColors.navy)),
                    trailing: option == _genderValue ? const Icon(Icons.check, color: AppColors.navy) : null,
                    onTap: () => Navigator.pop(context, option),
                  ))
              .toList(),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _genderValue = result;
        _gender.text = result.label;
      });
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
                    trailing: option == _maritalStatusValue ? const Icon(Icons.check, color: AppColors.navy) : null,
                    onTap: () => Navigator.pop(context, option),
                  ))
              .toList(),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _maritalStatusValue = result;
        _maritalStatus.text = result.label;
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) {
      setState(() => _photoPath = picked.path);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Just where the calendar opens if nothing's saved yet — never
      // shown as a value, so it's fine for this to be a guess.
      initialDate: _dateOfBirth ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dob.text = formatShortDate(picked);
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      // A freshly-picked local path (not yet an https URL) needs uploading
      // first; an unchanged photo is already a persisted URL.
      String? photoUrl = _photoPath;
      if (photoUrl != null && !photoUrl.startsWith('http')) {
        final fileName = photoUrl.split('/').last;
        photoUrl = await appState.uploads.upload(
          file: PickedUpload(path: photoUrl, fileName: fileName, isImage: true),
          folder: 'profile-photos',
        );
      }
      // Blank fields must become null, not '' — the backend's phone-number
      // validator rejects an empty string, so if the phone or address was
      // never filled in, echoing it back as '' failed validation and
      // blocked the whole save (including the field actually being
      // edited, e.g. the name).
      await appState.completeProfile(
        fullName: _fullName.text.trim(),
        phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        houseAddress: _address.text.trim().isEmpty ? null : _address.text.trim(),
        dateOfBirth: _dateOfBirth,
        profilePhotoUrl: photoUrl,
        gender: _genderValue,
        occupation: _occupation.text.trim().isEmpty ? null : _occupation.text.trim(),
        maritalStatus: _maritalStatusValue,
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
      navigator.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<AppState>().dashboardTheme;

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.foreground),
        title: Text(
          'Edit Profile',
          style: AppTextStyles.heading(color: theme.foreground, size: 18),
        ),
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickPhoto,
                    child: Stack(
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.accent.withValues(alpha: 0.25),
                            // BoxFit.contain rather than cover — there's no
                            // crop step at pick time, so covering the circle
                            // would zoom into whatever was centered in the
                            // original photo instead of showing all of it.
                            image: _photoPath != null
                                ? DecorationImage(
                                    image: imageProviderForPath(_photoPath!),
                                    fit: BoxFit.contain,
                                  )
                                : null,
                          ),
                          child: _photoPath == null
                              ? Icon(Icons.person, size: 48, color: theme.foreground)
                              : null,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.background,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: theme.onAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: _pickPhoto,
                    child: Text(
                      'Change Photo',
                      style: AppTextStyles.body(
                        color: theme.accent,
                        weight: FontWeight.w700,
                        size: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _EditableField(
                  label: 'Full Name',
                  theme: theme,
                  controller: _fullName,
                  focusNode: _fullNameFocus,
                  editable: _fullNameEditable,
                  hint: 'Enter your full name',
                  onToggleEdit: () {
                    setState(() => _fullNameEditable = !_fullNameEditable);
                    if (_fullNameEditable) {
                      FocusScope.of(context).requestFocus(_fullNameFocus);
                    }
                  },
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Date of Birth',
                  theme: theme,
                  controller: _dob,
                  editable: _dobEditable,
                  hint: 'Tap to select a date',
                  forceReadOnly: true,
                  onFieldTap: _dobEditable ? _pickDate : null,
                  extraTrailing: Icon(
                    Icons.calendar_today_outlined,
                    color: AppColors.navy,
                    size: 18,
                  ),
                  onToggleEdit:
                      () => setState(() => _dobEditable = !_dobEditable),
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'House Address',
                  theme: theme,
                  controller: _address,
                  focusNode: _addressFocus,
                  editable: _addressEditable,
                  hint: 'Enter your house address',
                  onToggleEdit: () {
                    setState(() => _addressEditable = !_addressEditable);
                    if (_addressEditable) {
                      FocusScope.of(context).requestFocus(_addressFocus);
                    }
                  },
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Phone Number',
                  theme: theme,
                  controller: _phone,
                  focusNode: _phoneFocus,
                  editable: _phoneEditable,
                  hint: 'Enter your phone number',
                  keyboardType: TextInputType.phone,
                  onToggleEdit: () {
                    setState(() => _phoneEditable = !_phoneEditable);
                    if (_phoneEditable) {
                      FocusScope.of(context).requestFocus(_phoneFocus);
                    }
                  },
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Gender',
                  theme: theme,
                  controller: _gender,
                  editable: _genderEditable,
                  hint: 'Tap to select a gender',
                  forceReadOnly: true,
                  onFieldTap: _genderEditable ? _pickGender : null,
                  extraTrailing: Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.navy,
                    size: 22,
                  ),
                  onToggleEdit: () => setState(() => _genderEditable = !_genderEditable),
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Occupation',
                  theme: theme,
                  controller: _occupation,
                  focusNode: _occupationFocus,
                  editable: _occupationEditable,
                  hint: 'Enter your occupation',
                  onToggleEdit: () {
                    setState(() => _occupationEditable = !_occupationEditable);
                    if (_occupationEditable) {
                      FocusScope.of(context).requestFocus(_occupationFocus);
                    }
                  },
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Marital Status',
                  theme: theme,
                  controller: _maritalStatus,
                  editable: _maritalStatusEditable,
                  hint: 'Tap to select a marital status',
                  forceReadOnly: true,
                  onFieldTap: _maritalStatusEditable ? _pickMaritalStatus : null,
                  extraTrailing: Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.navy,
                    size: 22,
                  ),
                  onToggleEdit: () => setState(() => _maritalStatusEditable = !_maritalStatusEditable),
                ),
                const SizedBox(height: 32),
                PillButton(
                  label: _saving ? 'Saving…' : 'Save Changes',
                  backgroundColor: theme.accent,
                  textColor: theme.onAccent,
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled field that is read-only until its pencil button is tapped,
/// so a stray tap can't accidentally change a saved value.
class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.label,
    required this.theme,
    required this.controller,
    required this.editable,
    required this.onToggleEdit,
    this.hint = '',
    this.keyboardType,
    this.extraTrailing,
    this.forceReadOnly = false,
    this.onFieldTap,
    this.focusNode,
  });

  final String label;
  final DashboardTheme theme;
  final TextEditingController controller;
  final bool editable;
  final VoidCallback onToggleEdit;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Widget? extraTrailing;
  final bool forceReadOnly;
  final VoidCallback? onFieldTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body(
            color: theme.foreground,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: PillTextField(
                hint: hint,
                controller: controller,
                focusNode: focusNode,
                readOnly: forceReadOnly || !editable,
                onTap: onFieldTap,
                keyboardType: keyboardType,
                obscureText: obscureText,
                validator: validator,
                trailing: extraTrailing,
                fillColor: editable ? AppColors.white : const Color(0xFFEDEDED),
                textColor: editable ? AppColors.navy : AppColors.hintGrey,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onToggleEdit,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      editable
                          ? theme.accent
                          : theme.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  editable ? Icons.check_rounded : Icons.edit_outlined,
                  color: editable ? theme.onAccent : theme.accent,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
