import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:homeservant/api/models/auth_user.dart';
import 'package:homeservant/models/user_role.dart';
import 'package:homeservant/routes/app_router.dart';
import 'package:homeservant/state/app_state.dart';

/// A signed-in AppState without touching the network: the fields the
/// router reads are set directly, the way a login response would.
AppState _signedIn(UserRole role, {bool profileCompleted = true, String name = 'Ada', String phone = '08012345678'}) {
  return AppState()
    ..isLoaded = true
    ..userId = 'user-1'
    ..role = role
    ..profileCompleted = profileCompleted
    ..fullName = name
    ..phoneNumber = phone;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('signed out', () {
    test('a protected route sends the user to Get Started', () {
      final appState = AppState()..isLoaded = true;
      expect(appRedirect(appState, '/dashboard'), '/get-started');
    });

    test('pre-auth screens (login, OTP) are left alone', () {
      final appState = AppState()..isLoaded = true;
      expect(appRedirect(appState, '/login-tenant'), isNull);
      expect(appRedirect(appState, '/verify-otp'), isNull);
    });

    test('nothing redirects before the saved session has loaded', () {
      expect(appRedirect(AppState(), '/dashboard'), isNull);
    });
  });

  group('profile setup guard', () {
    test('a finished profile reaches the dashboard even with gender/occupation/marital status unset', () {
      // The "sent back to finish setup on every login" bug: accounts
      // created before those fields were required have them null forever.
      final appState = _signedIn(UserRole.landlord);
      expect(appState.gender, isNull);
      expect(appRedirect(appState, '/dashboard'), isNull);
    });

    test('an unfinished tenant with no phone resumes at step 1', () {
      final appState = _signedIn(UserRole.tenant, profileCompleted: false, phone: '');
      expect(appRedirect(appState, '/dashboard'), '/signup-tenant-1');
    });

    test('an unfinished landlord with name and phone resumes at step 2', () {
      final appState = _signedIn(UserRole.landlord, profileCompleted: false);
      expect(appRedirect(appState, '/dashboard'), '/signup-landlord-2');
    });

    test('the marketplace is guarded too', () {
      final appState = _signedIn(UserRole.tenant, profileCompleted: false);
      expect(appRedirect(appState, '/marketplace'), '/signup-tenant-2');
    });

    test('vendors never go through the tenant/landlord wizard', () {
      final appState = _signedIn(UserRole.vendor, profileCompleted: false);
      expect(appRedirect(appState, '/dashboard'), isNull);
    });
  });

  group('signed-in users on entry screens', () {
    test('Get Started and the role pickers bounce to the dashboard', () {
      final appState = _signedIn(UserRole.tenant);
      expect(appRedirect(appState, '/get-started'), '/dashboard');
      expect(appRedirect(appState, '/login'), '/dashboard');
    });

    test("the login form itself isn't bounced, so its own post-login navigation runs", () {
      final appState = _signedIn(UserRole.tenant);
      expect(appRedirect(appState, '/login-tenant'), isNull);
      expect(appRedirect(appState, '/verify-otp'), isNull);
      expect(appRedirect(appState, '/admin-login'), isNull);
    });

    test('admins go to the console, never the tenant/landlord dashboard', () {
      final appState = _signedIn(UserRole.admin);
      expect(appRedirect(appState, '/login'), '/admin');
      expect(appRedirect(appState, '/dashboard'), '/admin');
    });
  });

  group('AuthUser.profileCompleted', () {
    Map<String, dynamic> json([Map<String, dynamic> extra = const {}]) => {
          'id': 'u1',
          'email': 'a@b.com',
          'role': 'TENANT',
          ...extra,
        };

    test('set when the server sent a completion time', () {
      expect(AuthUser.fromApi(json({'profileCompletedAt': '2026-09-26T00:00:00Z'})).profileCompleted, isTrue);
    });

    test('unset when the server sent null', () {
      expect(AuthUser.fromApi(json({'profileCompletedAt': null})).profileCompleted, isFalse);
    });

    test('treated as finished when an older backend omits the field', () {
      expect(AuthUser.fromApi(json()).profileCompleted, isTrue);
    });
  });
}
