import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../features/admin/admin_login_screen.dart';
import '../features/admin/admin_shell.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_role_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/signup_basics_screen.dart';
import '../features/auth/signup_details_screen.dart';
import '../features/auth/signup_role_screen.dart';
import '../features/auth/signup_screen.dart';
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
  if (appState.role == UserRole.admin) {
    context.go('/admin');
  } else if (!kIsWeb && appState.appLockEnabled && appState.appLockPin != null) {
    context.go('/app-lock-verify');
  } else {
    context.go('/dashboard');
  }
}

/// Google sign-in skips the OTP step, so a first-time Google account goes
/// through the same profile-completion wizard normal signup already
/// forces. A returning Google user who's already finished it skips
/// straight through, same as a normal login. Role comes from the account
/// Google matched to, not necessarily the screen the button was tapped
/// from — an existing landlord tapping "Sign in with Google" on the tenant
/// screen still lands in the landlord flow.
void _proceedAfterGoogleSignIn(BuildContext context) {
  final appState = context.read<AppState>();
  final setupRoute = _profileSetupRoute(appState);
  if (setupRoute != null) {
    context.push(setupRoute);
  } else {
    _proceedPastTwoFactor(context);
  }
}

/// Entry/pre-auth screens an unauthenticated user is allowed to sit on
/// without being bounced back to /get-started (see Guard A in the
/// `redirect` callback below). Includes verify-otp and login-2fa: those
/// are pushed *before* AppState.signup()/login() calls _applyUser (OTP
/// entry has to happen first), so the app is still unauthenticated while
/// sitting on them — without listing them here, Guard A would bounce the
/// user straight back to /get-started the instant they land on the OTP
/// screen. signup-*-1/2 and app-lock-verify aren't included: those are
/// only reached after verification, once _applyUser has already run.
const _preAuthPaths = {
  '/',
  '/get-started',
  '/login',
  '/login-landlord',
  '/login-tenant',
  '/login-2fa',
  '/signup',
  '/signup-landlord',
  '/signup-tenant',
  '/verify-otp',
  '/admin-login',
  '/forgot-password',
  '/reset-password',
};

/// Narrower subset of [_preAuthPaths]: genuine entry screens that should
/// send an *already*-authenticated returning user (see Guard B below)
/// straight to their dashboard instead of re-showing a login/signup form.
///
/// Deliberately excludes verify-otp, login-2fa, login-landlord,
/// login-tenant, admin-login, signup-landlord and signup-tenant. Those
/// seven become "authenticated" mid-flow — the instant OTP verification, a
/// plain email/password login, or Google sign-in succeeds, AppState's
/// _applyUser sets userId/role and calls notifyListeners() synchronously,
/// which is this router's refreshListenable, so `redirect` re-runs
/// immediately, while state.matchedLocation is still one of those seven
/// routes (refreshProfile()/_loadInitialData() are still in flight and
/// the screen's own onLoginSuccess/onVerified/onGoogleSignedIn callback
/// hasn't run yet — for login-landlord/login-tenant/admin-login
/// specifically, that callback is what navigates onward once
/// refreshProfile() has actually populated gender/occupation/marital
/// status, or — for admin-login — is what checks the just-logged-in
/// account's real role and force-logs-out/rejects a non-admin one). If
/// these seven stayed in this bounce set, Guard B would win that race and
/// dump the user straight on /dashboard/wherever on that stale,
/// partially-loaded AppState, preempting the screen's own "go to the
/// next step" navigation — e.g. skipping the profile-completion screens
/// after signup OTP, skipping the App Lock PIN gate after 2FA login,
/// sending a returning user with an already-complete profile through
/// Guard C into /signup-tenant-2 or /signup-landlord-2 on *every* login
/// (Guard C would see gender/occupation/maritalStatus still null — not
/// fetched yet, not actually missing — and, because that dead-end route
/// isn't itself in this bounce set, leave them stranded there instead of
/// ever reaching /dashboard), or — admin-login's own version of this bug
/// — letting a non-admin account that submits valid credentials on the
/// admin login form get bounced straight to its own ordinary dashboard
/// before AdminLoginScreen's "this account is not an admin account" check
/// (and forced logout) ever runs, since by the time that check's awaited
/// login() call resolves the screen has already been unmounted by Guard B.
///
/// The accepted tradeoff (same one already accepted for the others): a web
/// tab reloaded exactly on one of these seven routes with a still-valid
/// session won't auto-bounce to /dashboard the way /login or /get-started
/// would — the user would see the login form and have to navigate
/// manually. Mobile never hits this, since it always cold-starts at
/// initialLocation '/'.
const _returningUserBouncePaths = {
  '/',
  '/get-started',
  '/login',
  '/signup',
};

/// The router's own root Navigator, exposed so widgets that sit outside the
/// routed page tree — namely NotificationBannerOverlay, mounted in
/// HomeServantApp's `MaterialApp.builder` alongside SessionExpiredGate/
/// AppLockGate, above wherever `context.go`/`Navigator.of(context)` would
/// normally resolve to — can still push a screen (the notifications list)
/// on tap, the same way an in-page `Navigator.of(context).push` already
/// does from every dashboard's own NotificationBell.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Where an authenticated tenant/landlord who hasn't finished the signup
/// wizard should be sent, or null if they have (or aren't a
/// tenant/landlord at all — vendor/admin never go through this wizard).
///
/// "Finished" is decided solely by the server-owned
/// [AppState.profileCompleted] latch (backend `User.profileCompletedAt`),
/// never re-derived from individual profile fields here. Deriving it
/// locally is what kept breaking: (1) accounts created before gender/
/// occupation/marital status became required have those fields null
/// forever, so every such user was sent back to the wizard on every
/// login; and (2) the narrow login response doesn't carry those fields,
/// so a check against them raced the post-login profile fetch. The latch
/// comes back on the login response itself, is backfilled for every
/// existing account, and only ever goes false -> true.
///
/// The name/phone check below only picks *which* wizard step to resume
/// at for an account that is genuinely unfinished.
String? _profileSetupRoute(AppState appState) {
  if (appState.role != UserRole.tenant && appState.role != UserRole.landlord) return null;
  if (appState.profileCompleted) return null;
  final needsBasics = appState.fullName.trim().isEmpty || appState.phoneNumber.trim().isEmpty;
  if (appState.role == UserRole.landlord) {
    return needsBasics ? '/signup-landlord-1' : '/signup-landlord-2';
  }
  return needsBasics ? '/signup-tenant-1' : '/signup-tenant-2';
}

/// The two routes that represent "actually using the app" rather than a
/// step of getting signed in — the only places Guard C below steps in.
/// Deliberately not a block-list of every in-between auth screen (verify-
/// otp, login-2fa, app-lock-verify, the signup-*-1/2 screens themselves):
/// an allow-list here is safer, since it can't accidentally intercept some
/// other authenticated route this router grows later.
const _dashboardLikePaths = {'/dashboard', '/marketplace'};

/// The router's `redirect` rules, pulled out as a plain function of the
/// app state and the matched location so they can be unit-tested without
/// building any screens (see test/router_redirect_test.dart).
@visibleForTesting
String? appRedirect(AppState appState, String location) {
  if (!appState.isLoaded) return null;
  if (!appState.isAuthenticated) {
    // The session just ended (expired refresh token, forced sign-out,
    // etc.) while sitting on a protected route — without this branch,
    // the previous screen just stays on-screen underneath the session-
    // expired modal until the user manually taps "Log In Again" (see
    // SessionExpiredGate). GoRouter re-runs this the instant
    // AppState.notifyListeners() fires (refreshListenable: appState in
    // buildAppRouter), so this fires immediately, not on the next
    // navigation.
    if (!_preAuthPaths.contains(location)) return '/get-started';
    return null;
  }
  if (_returningUserBouncePaths.contains(location)) {
    return appState.role == UserRole.admin ? '/admin' : '/dashboard';
  }
  // An admin session has no business on the tenant/landlord dashboard
  // (reached, e.g., by a stale bookmark) — the console is the only
  // home screen that role has.
  if (appState.role == UserRole.admin && location == '/dashboard') {
    return '/admin';
  }
  // Guard C: catches an authenticated tenant/landlord who never
  // actually finished the signup wizard (e.g. closed the app or
  // reloaded the tab right after OTP verification) from reaching the
  // real app. See _profileSetupRoute for why this trusts only the
  // server's profileCompleted flag.
  if (_dashboardLikePaths.contains(location)) {
    final setupRoute = _profileSetupRoute(appState);
    if (setupRoute != null) return setupRoute;
  }
  return null;
}

GoRouter buildAppRouter(AppState appState) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: appState,
    redirect: (context, state) => appRedirect(appState, state.matchedLocation),
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
        builder: (context, state) => LoginRoleScreen(
          role: UserRole.landlord,
          onLoginSuccess: () => _proceedPastTwoFactor(context),
          onGoogleSignedIn: () => _proceedAfterGoogleSignIn(context),
          onRequiresTwoFactor: () => context.push('/login-2fa'),
          onRequiresEmailVerification: () => context.push('/verify-otp'),
          onSignUp: () => context.push('/signup-landlord'),
          onForgotPassword: () => context.push('/forgot-password', extra: UserRole.landlord),
        ),
      ),
      GoRoute(
        path: '/login-tenant',
        builder: (context, state) => LoginRoleScreen(
          role: UserRole.tenant,
          onLoginSuccess: () => _proceedPastTwoFactor(context),
          onGoogleSignedIn: () => _proceedAfterGoogleSignIn(context),
          onRequiresTwoFactor: () => context.push('/login-2fa'),
          onRequiresEmailVerification: () => context.push('/verify-otp'),
          onSignUp: () => context.push('/signup'),
          onForgotPassword: () => context.push('/forgot-password', extra: UserRole.tenant),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) {
          final role = (state.extra as UserRole?) ?? UserRole.tenant;
          return ForgotPasswordScreen(
            role: role,
            onCodeSent: (email) => context.push('/reset-password', extra: (role: role, email: email)),
          );
        },
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final extra = state.extra as ({UserRole role, String email})?;
          return ResetPasswordScreen(
            role: extra?.role ?? UserRole.tenant,
            email: extra?.email ?? '',
            onReset: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password reset — log in with your new password')),
              );
              context.go(extra?.role == UserRole.landlord ? '/login-landlord' : '/login-tenant');
            },
          );
        },
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
        builder: (context, state) => SignupRoleScreen(
          role: UserRole.tenant,
          onContinue: (email) {
            context.read<AppState>().setEmail(email);
            context.push('/verify-otp');
          },
          onGoogleSignedIn: () => _proceedAfterGoogleSignIn(context),
        ),
      ),
      GoRoute(
        path: '/signup-landlord',
        builder: (context, state) => SignupRoleScreen(
          role: UserRole.landlord,
          onContinue: (email) {
            context.read<AppState>().setEmail(email);
            context.push('/verify-otp');
          },
          onGoogleSignedIn: () => _proceedAfterGoogleSignIn(context),
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
        builder: (context, state) => SignupBasicsScreen(
          role: UserRole.landlord,
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
        builder: (context, state) => SignupDetailsScreen(
          role: UserRole.landlord,
          onFinish: () => context.go('/dashboard'),
        ),
      ),
      GoRoute(
        path: '/signup-tenant-1',
        builder: (context, state) => SignupBasicsScreen(
          role: UserRole.tenant,
          onContinue: (fields) {
            context.read<AppState>().setProfileBasics(
                  name: fields['name'] ?? '',
                  phone: fields['phone'] ?? '',
                );
            context.push('/signup-tenant-2');
          },
        ),
      ),
      GoRoute(
        path: '/signup-tenant-2',
        builder: (context, state) => SignupDetailsScreen(
          role: UserRole.tenant,
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
      GoRoute(
        // Deliberately not linked from anywhere in the normal tenant/
        // landlord/vendor UI — reached only by navigating here directly.
        // Admin accounts are never self-registered (see AuthService.signup),
        // so this is purely a sign-in screen, no "Sign Up" link.
        path: '/admin-login',
        builder: (context, state) => AdminLoginScreen(onLoginSuccess: () => context.go('/admin')),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminShell(),
      ),
    ],
  );
}
