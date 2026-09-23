import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../features/auth/login_landlord_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/login_tenant_screen.dart';
import '../features/auth/signup_landlord1_screen.dart';
import '../features/auth/signup_landlord2_screen.dart';
import '../features/auth/signup_landlord_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/signup_tenant1_screen.dart';
import '../features/auth/signup_tenant2_screen.dart';
import '../features/auth/signup_tenant_screen.dart';
import '../features/auth/verify_otp_screen.dart';
import '../features/landlord/landlord_dashboard_screen.dart';
import '../features/dashboard/tenant_dashboard_screen.dart';
import '../features/Market place/marketplace_navigator_host.dart';
import '../features/onboarding/get_started_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/splash/web_landing_screen.dart';
import '../models/user_role.dart';
import '../state/app_state.dart';
import '../widgets/app_lock_screen.dart';

/// After identity is confirmed (2FA passed, or not required), goes straight
/// to the dashboard unless App Lock is on — in which case the PIN gate is
/// interposed first, so a device-level lock can't be skipped just because
/// this login flow is mocked (there's no real backend to gate on).
///
/// App Lock doesn't apply on web ([kIsWeb]) — see [AppLockGate] — so this
/// always goes straight to the dashboard there, even if the setting is on
/// from another platform's session.
void _proceedPastTwoFactor(BuildContext context) {
  final appState = context.read<AppState>();
  if (!kIsWeb && appState.appLockEnabled && appState.appLockPin != null) {
    context.go('/app-lock-verify');
  } else {
    context.go('/dashboard');
  }
}

GoRouter buildAppRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => kIsWeb
            ? WebLandingScreen(
                // "Get Started" on the marketing site goes straight to
                // role-selection sign-up, skipping the Login/Sign Up choice
                // screen — a visitor landing here has already decided they
                // want to sign up.
                onGetStarted: () => context.push('/signup'),
                onLogin: () => context.push('/login'),
                // Landlords who want to list before full launch skip the
                // role-choice screen entirely and land straight on landlord
                // sign-up, matching the shortcut '/login' and '/signup' take
                // once a role is already known.
                onGetOnboarded: () {
                  context.read<AppState>().selectRole(UserRole.landlord);
                  context.push('/signup-landlord');
                },
              )
            : SplashScreen(onExplore: () => context.push('/get-started')),
      ),
      GoRoute(
        path: '/get-started',
        builder: (context, state) => GetStartedScreen(
          onLogin: () => context.push('/login'),
          onSignUp: () => context.push('/signup'),
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(
          onRoleSelected: (role) {
            context.read<AppState>().selectRole(role);
            if (role == UserRole.landlord) {
              context.push('/login-landlord');
            } else {
              context.push('/login-tenant');
            }
          },
        ),
      ),
      GoRoute(
        path: '/login-landlord',
        builder: (context, state) => LoginLandlordScreen(
          onLoginSuccess: () => _proceedPastTwoFactor(context),
          onRequiresTwoFactor: () => context.push('/login-2fa'),
          onSignUp: () => context.push('/signup-landlord'),
        ),
      ),
      GoRoute(
        path: '/login-tenant',
        builder: (context, state) => LoginTenantScreen(
          onLoginSuccess: () => _proceedPastTwoFactor(context),
          onRequiresTwoFactor: () => context.push('/login-2fa'),
          onSignUp: () => context.push('/signup'),
        ),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => SignupScreen(
          onRoleSelected: (role) {
            context.read<AppState>().selectRole(role);
            if (role == UserRole.landlord) {
              context.push('/signup-landlord');
            } else {
              context.push('/signup-tenant');
            }
          },
        ),
      ),
      GoRoute(
        path: '/signup-tenant',
        builder: (context, state) => SignupTenantScreen(
          onContinue: (email) {
            context.read<AppState>().setEmail(email);
            context.push('/verify-otp');
          },
        ),
      ),
      GoRoute(
        path: '/signup-landlord',
        builder: (context, state) => SignupLandlordScreen(
          onContinue: (email) {
            context.read<AppState>().setEmail(email);
            context.push('/verify-otp');
          },
        ),
      ),
      GoRoute(
        path: '/verify-otp',
        builder: (context, state) {
          final appState = context.watch<AppState>();
          return VerifyOtpScreen(
            role: appState.role,
            email: appState.email,
            onVerified: () {
              if (appState.role == UserRole.landlord) {
                context.push('/signup-landlord-1');
              } else {
                context.push('/signup-tenant-1');
              }
            },
          );
        },
      ),
      GoRoute(
        path: '/signup-landlord-1',
        builder: (context, state) => SignupLandlord1Screen(
          onContinue: (fields) {
            context.read<AppState>().setProfileBasics(
                  name: fields['name'] ?? '',
                  phone: fields['phone'] ?? '',
                  houseAddress: fields['houseAddress'],
                );
            context.push('/signup-landlord-2');
          },
        ),
      ),
      GoRoute(
        path: '/signup-landlord-2',
        builder: (context, state) => SignupLandlord2Screen(
          onFinish: () => context.go('/dashboard'),
        ),
      ),
      GoRoute(
        path: '/signup-tenant-1',
        builder: (context, state) => SignupTenant1Screen(
          onContinue: (fields) {
            context.read<AppState>().setProfileBasics(
                  name: fields['name'] ?? '',
                  phone: fields['phone'] ?? '',
                  referralCode: fields['referral'],
                );
            context.push('/signup-tenant-2');
          },
        ),
      ),
      GoRoute(
        path: '/signup-tenant-2',
        builder: (context, state) => SignupTenant2Screen(
          onFinish: () => context.go('/dashboard'),
        ),
      ),
      GoRoute(
        path: '/login-2fa',
        builder: (context, state) {
          final appState = context.watch<AppState>();
          return VerifyOtpScreen(
            role: appState.role,
            email: appState.email.isEmpty ? 'your email' : appState.email,
            purpose: OtpPurpose.login2fa,
            onVerified: () => _proceedPastTwoFactor(context),
          );
        },
      ),
      GoRoute(
        path: '/app-lock-verify',
        builder: (context, state) {
          final appState = context.watch<AppState>();
          final pin = appState.appLockPin;
          // Guards against a route ever being reached without a PIN set —
          // shouldn't happen since _proceedPastTwoFactor only routes here when
          // one exists, but going straight through is safer than a crash.
          if (pin == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/dashboard'));
            return const SizedBox.shrink();
          }
          return AppLockScreen(expectedPin: pin, onUnlocked: () => context.go('/dashboard'));
        },
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) {
          final role = context.watch<AppState>().role;
          return role.isLandlord ? const LandlordDashboardScreen() : const TenantDashboardScreen();
        },
      ),
      GoRoute(
        // A real go_router route (rather than a bare Navigator.push from the
        // dashboard) so entering the Marketplace adds its own browser
        // history entry. Without this, none of the Marketplace's internal
        // navigation (all imperative Navigator.push, for screens as varied
        // as vendor onboarding and chat threads) ever touched the URL, so
        // pressing the browser's back button while inside it fell through
        // to whatever URL preceded '/dashboard' — typically the login
        // screen — instead of landing back on the dashboard.
        path: '/marketplace',
        builder: (context, state) {
          final theme = context.watch<AppState>().dashboardTheme;
          return MarketplaceNavigatorHost(theme: theme);
        },
      ),
    ],
  );
}
