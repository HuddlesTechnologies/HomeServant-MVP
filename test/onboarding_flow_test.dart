import 'package:flutter_test/flutter_test.dart';

import 'package:homeservant/app.dart';

/// Screen-to-screen navigation up to each login/signup form. Everything
/// past a form submission talks to the real API, so it isn't covered here;
/// the routing rules those flows depend on are unit-tested in
/// router_redirect_test.dart.
Future<void> _openFromSplash(WidgetTester tester, String entry) async {
  await tester.pumpWidget(const HomeServantApp());
  // The splash screen's Ken Burns background animation repeats forever, so
  // pumpAndSettle() here would never converge — pump one bounded frame
  // instead. Its layout is static, so EXPLORE is already tappable.
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('EXPLORE'));
  await tester.pumpAndSettle();
  expect(find.text('Login'), findsOneWidget);
  expect(find.text('Sign Up'), findsOneWidget);
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

void main() {
  for (final role in ['Tenant', 'Landlord']) {
    testWidgets('Get Started -> Sign Up -> $role signup form', (tester) async {
      await _openFromSplash(tester, 'Sign Up');
      expect(find.text('Sign up as a Tenant'), findsOneWidget);
      expect(find.text('Sign up as a Landlord'), findsOneWidget);

      await tester.tap(find.text('Sign up as a $role'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('Get Started -> Login -> $role login form', (tester) async {
      await _openFromSplash(tester, 'Login');
      expect(find.text('Login as a Tenant'), findsOneWidget);
      expect(find.text('Login as a Landlord'), findsOneWidget);

      await tester.tap(find.text('Login as a $role'));
      await tester.pumpAndSettle();

      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
    });
  }
}
