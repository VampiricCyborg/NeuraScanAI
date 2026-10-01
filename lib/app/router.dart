/// Navigation.
///
/// The interesting part is the redirect. Two gates have to hold from every route:
/// a signed-out user cannot reach anything but sign-in, and a signed-in user who
/// has not accepted the current consent text cannot reach anything but the consent
/// screen. Putting both in one redirect rather than checking them per screen means a
/// new screen is covered by them the moment it is added, instead of only if its
/// author remembered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/consent_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/profile/privacy_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/report/export/report_model.dart';
import '../features/report/report_screen.dart';
import '../features/report/screens/results_views.dart';
import '../features/session/session_screen.dart';
import '../features/session/summary_screen.dart';
import '../features/trends/trends_screen.dart';
import 'providers.dart';
import 'shell.dart';

/// Every route path, in one place so that a typo is a compile error.
abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const consent = '/consent';
  static const home = '/home';
  static const trends = '/trends';
  static const profile = '/profile';
  static const privacy = '/profile/privacy';
  static const session = '/session';
  static const summary = '/session/summary';
  static const report = '/report';
  static const metric = '/metric';
  static const reportPreview = '/report/preview';
}

/// Routes reachable without being signed in.
///
/// The splash screen is deliberately not here. It is a loading state rather than a
/// destination, and treating it as a valid place for a signed-out user to sit left them
/// stranded on it: once the auth state resolved to "signed out", the redirect saw a public
/// route and allowed it, so the app never moved off the spinner.
const _publicRoutes = {Routes.onboarding, Routes.login};

/// The app's router.
final routerProvider = Provider<GoRouter>((ref) {
  // Held rather than watched: rebuilding the router would drop the navigation
  // stack. The notifier below tells go_router to re-evaluate its redirect instead.
  final refresh = _AuthRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.consent,
        builder: (context, state) => const ConsentScreen(),
      ),

      // The session runs outside the navigation shell. It is a single task at a
      // time under a countdown, and a bottom navigation bar offering a way out
      // mid-task would cost sessions rather than save them.
      GoRoute(
        path: Routes.session,
        builder: (context, state) => const SessionScreen(),
      ),
      GoRoute(
        path: Routes.summary,
        builder: (context, state) =>
            SummaryScreen(sessionId: state.uri.queryParameters['sessionId']),
      ),
      GoRoute(
        path: Routes.report,
        builder: (context, state) => const ReportScreen(),
      ),
      GoRoute(
        path: Routes.reportPreview,
        builder: (context, state) =>
            ReportPreviewScreen(model: state.extra! as ReportModel),
      ),
      GoRoute(
        path: Routes.metric,
        builder: (context, state) => MetricDetailScreen(
          metricKey: state.uri.queryParameters['key'] ?? '',
        ),
      ),

      // The three tabs share a shell so switching between them keeps their state.
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: Routes.trends,
            builder: (context, state) => const TrendsScreen(),
          ),
          GoRoute(
            path: Routes.profile,
            builder: (context, state) => const ProfileScreen(),
            routes: [
              GoRoute(
                path: 'privacy',
                builder: (context, state) => const PrivacyScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Decides where a navigation attempt should actually land.
///
/// Returns null to allow the requested route.
String? _redirect(Ref ref, GoRouterState state) {
  final authState = ref.read(authStateProvider);
  final location = state.matchedLocation;

  // Hold on the splash screen until the stored session has been read. Redirecting
  // to sign-in while that is still loading would flash the login screen at every
  // launch for a user who is signed in.
  if (authState.isLoading) {
    return location == Routes.splash ? null : Routes.splash;
  }

  final signedIn = authState.value != null;

  if (!signedIn) {
    // Leaving the splash screen once loading is done. A first launch goes through the
    // onboarding, which explains the personal-baseline idea before asking for anything;
    // its skip button reaches sign-in in one tap for anyone who has seen it.
    if (location == Routes.splash) return Routes.onboarding;
    return _publicRoutes.contains(location) ? null : Routes.login;
  }

  // Signed in: the profile row may still be loading, and the consent gate cannot be
  // judged until it has.
  final profile = ref.read(profileProvider);
  if (profile.isLoading) {
    return location == Routes.splash ? null : Routes.splash;
  }

  if (!(profile.value?.hasCurrentConsent ?? false)) {
    return location == Routes.consent ? null : Routes.consent;
  }

  // Signed in and consented: there is nothing for them on the pre-auth screens, and
  // nothing left on the splash screen either.
  if (_publicRoutes.contains(location) ||
      location == Routes.consent ||
      location == Routes.splash) {
    return Routes.home;
  }

  return null;
}

/// Prompts go_router to re-run its redirect when auth or consent changes.
///
/// go_router needs a [Listenable]; Riverpod gives streams and futures. This is the
/// adapter, and it is the whole reason the router is not simply rebuilt: rebuilding
/// it would reset the navigation stack on every settings change.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    _subscriptions = [
      ref.listen(authStateProvider, (_, _) => notifyListeners()),
      ref.listen(profileProvider, (_, _) => notifyListeners()),
    ];
  }

  late final List<ProviderSubscription<Object?>> _subscriptions;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    super.dispose();
  }
}
