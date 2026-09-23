import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:homeservant/app.dart';

void main() {
  testWidgets('Get Started -> Sign Up -> role select -> landlord signup form', (
    tester,
  ) async {
    await tester.pumpWidget(const HomeServantApp());
    // The splash screen's Ken Burns background animation repeats forever, so
    // pumpAndSettle() here would never converge — pump one bounded frame
    // instead. Its layout is static and unconditional, so this is enough for
    // the EXPLORE button to be present and tappable.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('EXPLORE'));
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);

    await tester.tap(find.text('Sign Up'));
    await tester.pumpAndSettle();

    expect(find.text('Sign up as a Tenant'), findsOneWidget);
    expect(find.text('Sign up as a Landlord'), findsOneWidget);

    await tester.tap(find.text('Sign up as a Landlord'));
    await tester.pumpAndSettle();

    expect(find.text('Sign Up'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets(
    'Tenant signup -> OTP -> onboarding 1 -> onboarding 2 -> dashboard',
    (tester) async {
      await tester.pumpWidget(const HomeServantApp());
      // See the comment on the other tests' equivalent line — the splash
      // screen's repeating Ken Burns animation means pumpAndSettle() here
      // would never converge.
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('EXPLORE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign up as a Tenant'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'tenant@example.com');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Verify Your Email'), findsOneWidget);
      final otpBoxes = find.byType(TextField);
      for (var i = 0; i < 4; i++) {
        await tester.enterText(otpBoxes.at(i), '1');
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome Onboard'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'John Tenant');
      await tester.enterText(find.byType(TextField).at(1), '08099998888');
      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Add a Photo'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Categories'), findsOneWidget);
    },
  );

  testWidgets('Get Started -> Login -> role select -> landlord login form', (
    tester,
  ) async {
    await tester.pumpWidget(const HomeServantApp());
    // The splash screen's Ken Burns background animation repeats forever, so
    // pumpAndSettle() here would never converge — pump one bounded frame
    // instead. Its layout is static and unconditional, so this is enough for
    // the EXPLORE button to be present and tappable.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('EXPLORE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Login as a Tenant'), findsOneWidget);
    expect(find.text('Login as a Landlord'), findsOneWidget);

    await tester.tap(find.text('Login as a Landlord'));
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('Get Started -> Login -> tenant leads to a tenant login form', (
    tester,
  ) async {
    await tester.pumpWidget(const HomeServantApp());
    // The splash screen's Ken Burns background animation repeats forever, so
    // pumpAndSettle() here would never converge — pump one bounded frame
    // instead. Its layout is static and unconditional, so this is enough for
    // the EXPLORE button to be present and tappable.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('EXPLORE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login as a Tenant'));
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('Landlord dashboard: Log Out returns to Get Started', (
    tester,
  ) async {
    await tester.pumpWidget(const HomeServantApp());
    // The splash screen's Ken Burns background animation repeats forever, so
    // pumpAndSettle() here would never converge — pump one bounded frame
    // instead. Its layout is static and unconditional, so this is enough for
    // the EXPLORE button to be present and tappable.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('EXPLORE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login as a Landlord'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('My Properties'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Log Out'), findsOneWidget);

    await tester.ensureVisible(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
  });

  testWidgets('Tenant dashboard: Log Out returns to Get Started', (
    tester,
  ) async {
    await tester.pumpWidget(const HomeServantApp());
    // The splash screen's Ken Burns background animation repeats forever, so
    // pumpAndSettle() here would never converge — pump one bounded frame
    // instead. Its layout is static and unconditional, so this is enough for
    // the EXPLORE button to be present and tappable.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('EXPLORE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login as a Tenant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Log Out'), findsOneWidget);

    await tester.ensureVisible(find.text('Log Out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
  });

  testWidgets(
    'Landlord signup -> OTP -> onboarding 1 -> onboarding 2 -> dashboard',
    (tester) async {
      await tester.pumpWidget(const HomeServantApp());
      // See the comment on the other tests' equivalent line — the splash
      // screen's repeating Ken Burns animation means pumpAndSettle() here
      // would never converge.
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('EXPLORE'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign up as a Landlord'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'landlord@example.com');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Verify Your Email'), findsOneWidget);
      final otpBoxes = find.byType(TextField);
      for (var i = 0; i < 4; i++) {
        await tester.enterText(otpBoxes.at(i), '1');
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome Onboard'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Jane Landlord');
      await tester.enterText(find.byType(TextField).at(1), '08012345678');
      await tester.enterText(find.byType(TextField).at(2), '1 Main Street');
      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Add a Photo'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('My Properties'), findsOneWidget);
    },
  );
}
