// Guards for bugs that were fixed and then came back. Each test names the
// symptom it protects against, so a failure here says what users would see.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homeservant/api/api_config.dart' show googleServerClientId;
import 'package:homeservant/core/theme/app_colors.dart';
import 'package:homeservant/core/theme/app_text_styles.dart';
import 'package:homeservant/core/theme/app_theme.dart';

/// vercel.json's Content-Security-Policy, split into directive -> sources.
Map<String, List<String>> _csp() {
  final config = jsonDecode(File('vercel.json').readAsStringSync()) as Map<String, dynamic>;
  final headers = [
    for (final rule in config['headers'] as List) ...(rule['headers'] as List).cast<Map<String, dynamic>>(),
  ];
  final policy = headers.firstWhere((h) => h['key'] == 'Content-Security-Policy')['value'] as String;
  return {
    for (final directive in policy.split(';').map((d) => d.trim()).where((d) => d.isNotEmpty))
      directive.split(RegExp(r'\s+')).first: directive.split(RegExp(r'\s+')).skip(1).toList(),
  };
}

String _header(String key) {
  final config = jsonDecode(File('vercel.json').readAsStringSync()) as Map<String, dynamic>;
  for (final rule in config['headers'] as List) {
    for (final h in (rule['headers'] as List).cast<Map<String, dynamic>>()) {
      if (h['key'] == key) return h['value'] as String;
    }
  }
  return '';
}

void main() {
  group('Continue with Google', () {
    test('web and mobile use the same Google client ID (else the server rejects one of them)', () {
      final html = File('web/index.html').readAsStringSync();
      final match = RegExp(r'name="google-signin-client_id"\s+content="([^"]+)"').firstMatch(html);
      expect(match, isNotNull, reason: 'web/index.html lost its google-signin-client_id meta tag');
      expect(match!.group(1), googleServerClientId);
    });

    test("the site's security policy still lets Google's button load, show its popup and talk to Google", () {
      final csp = _csp();
      expect(csp['script-src'], contains('https://accounts.google.com'));
      expect(csp['style-src'], contains('https://accounts.google.com'));
      expect(csp['frame-src'], contains('https://accounts.google.com'));
      expect(csp['connect-src'], contains('https://accounts.google.com'));
      // Google's button refuses to work when the browser sends no origin.
      expect(_header('Referrer-Policy'), isNot(anyOf('no-referrer', 'same-origin')));
      // Its popup reports back to this page; a strict opener policy cuts that off.
      expect(_header('Cross-Origin-Opener-Policy'), isNot('same-origin'));
    });

    test('the security policy still allows the API the deployed site signs in against', () {
      final config = jsonDecode(File('vercel.json').readAsStringSync()) as Map<String, dynamic>;
      final match = RegExp(r'API_BASE_URL=(\S+)').firstMatch(config['buildCommand'] as String);
      expect(match, isNotNull, reason: "vercel.json's build no longer sets API_BASE_URL");
      final api = Uri.parse(match!.group(1)!);
      expect(_csp()['connect-src'], contains('${api.scheme}://${api.host}'));
      expect(_csp()['connect-src'], contains('wss://${api.host}'));
    });
  });

  group('Invisible text on the web build', () {
    test("the security policy allows Flutter's engine and fonts (blocked fonts draw text with no glyphs)", () {
      final csp = _csp();
      expect(csp['script-src'], contains('https://www.gstatic.com'));
      expect(csp['font-src'], contains('https://fonts.gstatic.com'));
      expect(csp['connect-src'], contains('https://fonts.gstatic.com'));
    });

    testWidgets('the date-of-birth calendar draws its text in the bundled font, in navy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDatePicker(
                  context: context,
                  initialDate: DateTime(2000, 9, 15),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2010),
                  builder: AppTheme.datePickerBuilder,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The month/year toggle and OK/Cancel are the parts that went blank.
      for (final label in ['September 2000', 'OK', 'Cancel']) {
        final finder = find.text(label);
        expect(finder, findsWidgets, reason: '"$label" is missing from the calendar');
        final rich = tester.widget<RichText>(find.descendant(of: finder.first, matching: find.byType(RichText)).first);
        final style = rich.text.style!;
        expect(style.fontFamily, AppTextStyles.bodyFont, reason: '"$label" fell back to a downloaded font');
        // Navy (Material may soften it, but never below readable) on the
        // calendar's white.
        expect(style.color, isNotNull, reason: '"$label" has no color of its own');
        expect(style.color!.withValues(alpha: 1), AppColors.navy, reason: '"$label" is not navy');
        expect(style.color!.a, greaterThanOrEqualTo(0.5), reason: '"$label" is too faint to read');
      }
    });
  });
}
