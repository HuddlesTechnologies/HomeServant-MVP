import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import '../api/models/verification.dart';
import 'field_error_text.dart';
import 'pill_text_field.dart';

/// The "Means of Identification" bottom-sheet picker plus its conditional,
/// per-ID-type-formatted number field — shared by the landlord and tenant
/// second signup steps. Both are required: the screen calls [validate] via
/// a GlobalKey before submitting, then reads [selectedType]/[number] and
/// saves them for admin review (VerificationRepository).
class IdentificationPickerField extends StatefulWidget {
  const IdentificationPickerField({super.key, required this.labelColor, required this.errorColor});

  final Color labelColor;
  final Color errorColor;

  @override
  State<IdentificationPickerField> createState() => IdentificationPickerFieldState();
}

class IdentificationPickerFieldState extends State<IdentificationPickerField> {
  static const _idOptions = ['NIN', "Driver's License", "Voter's Card", 'International Passport'];

  final _idNumberController = TextEditingController();
  String? _identification;
  String? _typeError;
  String? _numberError;

  IdDocumentType? get selectedType => IdDocumentType.fromLabel(_identification);
  String get number => _idNumberController.text.trim();

  /// Both an ID type and a correctly formatted number. Shows the errors.
  bool validate() {
    final format = _idNumberFormat;
    final number = _idNumberController.text.trim();
    String? typeError;
    String? numberError;
    if (_identification == null || format == null) {
      typeError = 'Select your means of identification';
    } else if (number.isEmpty) {
      numberError = 'Enter your $_identification number';
    } else if (_identification == 'NIN' && number.length != 11) {
      numberError = 'Your NIN must be 11 digits';
    } else if (_identification == "Voter's Card" && number.length != 19) {
      numberError = "Your Voter's Card number must be 19 characters";
    } else if (_identification == "Driver's License" && (number.length < 8 || number.length > 12)) {
      numberError = "A driver's licence number is 8 to 12 letters and digits";
    } else if (_identification == 'International Passport' && !RegExp(r'^[A-Z][0-9]{8}$').hasMatch(number)) {
      numberError = 'A passport number is a letter followed by 8 digits';
    }
    setState(() {
      _typeError = typeError;
      _numberError = numberError;
    });
    return typeError == null && numberError == null;
  }

  @override
  void dispose() {
    _idNumberController.dispose();
    super.dispose();
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
        _typeError = null;
        _numberError = null;
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledDropdownField(
          label: 'Means of Identification',
          value: _identification ?? 'Select your means of identification',
          labelColor: widget.labelColor,
          onTap: _pickIdentification,
        ),
        FieldErrorText(_typeError, color: widget.errorColor),
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
          FieldErrorText(_numberError, color: widget.errorColor),
        ],
      ],
    );
  }
}
