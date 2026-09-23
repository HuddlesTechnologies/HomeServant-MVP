import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
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
  static const _dummyFirstName = 'Jane';
  static const _dummyLastName = 'Doe';
  static const _dummyAddress = '15 Seyi Coker Street, Agege, Lagos';
  static const _dummyPhone = '0801 234 5678';
  static const _dummyEmail = 'jane.doe@example.com';
  static const _dummyPassword = 'homeservant123';
  static final _dummyDob = DateTime(1996, 4, 12);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _dob;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _password;
  late DateTime _dateOfBirth;
  String? _photoPath;
  bool _obscurePassword = true;

  bool _firstNameEditable = false;
  bool _lastNameEditable = false;
  bool _dobEditable = false;
  bool _addressEditable = false;
  bool _phoneEditable = false;
  bool _emailEditable = false;
  bool _passwordEditable = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _firstName = TextEditingController(
      text:
          appState.firstName.isNotEmpty ? appState.firstName : _dummyFirstName,
    );
    _lastName = TextEditingController(
      text: appState.lastName.isNotEmpty ? appState.lastName : _dummyLastName,
    );
    _dateOfBirth = appState.dateOfBirth ?? _dummyDob;
    _dob = TextEditingController(text: formatShortDate(_dateOfBirth));
    _address = TextEditingController(
      text:
          appState.houseAddress.isNotEmpty
              ? appState.houseAddress
              : _dummyAddress,
    );
    _phone = TextEditingController(
      text:
          appState.phoneNumber.isNotEmpty ? appState.phoneNumber : _dummyPhone,
    );
    _email = TextEditingController(
      text: appState.email.isNotEmpty ? appState.email : _dummyEmail,
    );
    _password = TextEditingController(
      text: appState.password.isNotEmpty ? appState.password : _dummyPassword,
    );
    _photoPath = appState.profilePhotoPath;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _dob.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _photoPath = picked.path);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth,
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

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final appState = context.read<AppState>();
    appState.setProfilePhoto(_photoPath);
    appState.updateProfileDetails(
      houseAddress: _address.text.trim(),
      phoneNumber: _phone.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      dateOfBirth: _dateOfBirth,
    );
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profile updated')));
    Navigator.of(context).pop();
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
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: theme.accent.withValues(alpha: 0.25),
                          backgroundImage:
                              _photoPath != null
                                  ? imageProviderForPath(_photoPath!)
                                  : null,
                          child:
                              _photoPath == null
                                  ? Icon(
                                    Icons.person,
                                    size: 48,
                                    color: theme.foreground,
                                  )
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
                  label: 'First Name',
                  theme: theme,
                  controller: _firstName,
                  editable: _firstNameEditable,
                  onToggleEdit:
                      () => setState(
                        () => _firstNameEditable = !_firstNameEditable,
                      ),
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Last Name',
                  theme: theme,
                  controller: _lastName,
                  editable: _lastNameEditable,
                  onToggleEdit:
                      () => setState(
                        () => _lastNameEditable = !_lastNameEditable,
                      ),
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Date of Birth',
                  theme: theme,
                  controller: _dob,
                  editable: _dobEditable,
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
                  editable: _addressEditable,
                  onToggleEdit:
                      () =>
                          setState(() => _addressEditable = !_addressEditable),
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Phone Number',
                  theme: theme,
                  controller: _phone,
                  editable: _phoneEditable,
                  keyboardType: TextInputType.phone,
                  onToggleEdit:
                      () => setState(() => _phoneEditable = !_phoneEditable),
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Email',
                  theme: theme,
                  controller: _email,
                  editable: _emailEditable,
                  keyboardType: TextInputType.emailAddress,
                  onToggleEdit:
                      () => setState(() => _emailEditable = !_emailEditable),
                  validator: (value) {
                    if (value == null || !value.contains('@')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                _EditableField(
                  label: 'Password',
                  theme: theme,
                  controller: _password,
                  editable: _passwordEditable,
                  obscureText: _obscurePassword,
                  onToggleEdit:
                      () => setState(
                        () => _passwordEditable = !_passwordEditable,
                      ),
                  extraTrailing: IconButton(
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                PillButton(
                  label: 'Save Changes',
                  backgroundColor: theme.accent,
                  textColor: theme.onAccent,
                  onPressed: _save,
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
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.extraTrailing,
    this.forceReadOnly = false,
    this.onFieldTap,
  });

  final String label;
  final DashboardTheme theme;
  final TextEditingController controller;
  final bool editable;
  final VoidCallback onToggleEdit;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Widget? extraTrailing;
  final bool forceReadOnly;
  final VoidCallback? onFieldTap;

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
                hint: '',
                controller: controller,
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
