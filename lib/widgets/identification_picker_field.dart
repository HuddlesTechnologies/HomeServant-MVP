import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_text_styles.dart';
import 'pill_text_field.dart';

/// The "Means of Identification" bottom-sheet picker plus its conditional,
/// per-ID-type-formatted number field — shared by the landlord and tenant
/// second signup steps. Neither screen's submit call reads the picked
/// identification or its number back out (see each screen's own comment:
/// this step has no backend KYC/verification model yet, so it's collected
/// only for UI completeness), so this widget owns that bit of state
/// entirely on its own rather than reporting it back up.
class IdentificationPickerField extends StatefulWidget {
  const IdentificationPickerField({super.key, required this.labelColor});

  final Color labelColor;

  @override
  State<IdentificationPickerField> createState() => _IdentificationPickerFieldState();
}

class _IdentificationPickerFieldState extends State<IdentificationPickerField> {
  static const _idOptions = ['NIN', "Driver's License", "Voter's Card", 'International Passport'];

  final _idNumberController = TextEditingController();
  String? _identification;

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
      ],
    );
  }
}
