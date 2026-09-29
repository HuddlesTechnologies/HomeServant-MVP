import 'package:flutter/services.dart';

/// Formats a whole number with thousands separators, e.g. `2500000` ->
/// `2,500,000`. Shared by every price input across the app (the tenant
/// dashboard's price filter, the marketplace "List a Product" price field)
/// so typed and displayed amounts are always comma-grouped the same way.
String formatWithThousandsSeparator(num value) {
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Live-formats a numeric [TextField] with thousands separators as the
/// user types, keeping the cursor at the end of the formatted value.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(',', '');
    if (digitsOnly.isEmpty) return newValue.copyWith(text: '');
    final formatted = formatWithThousandsSeparator(int.parse(digitsOnly));
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

/// "₦1,200,000" from a naira amount.
String nairaLabel(num naira) => '₦${formatWithThousandsSeparator(naira)}';

/// "₦1,200,000" from a kobo amount (payments are stored in kobo).
String nairaLabelFromKobo(int kobo) => nairaLabel(kobo / 100);
