import 'package:flutter/widgets.dart';

/// Non-web builds never render Google's own button — see
/// google_web_button_web.dart for why web needs it.
Widget buildGoogleWebButton() => const SizedBox.shrink();
