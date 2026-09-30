/// The two navigation gates.
///
/// These are the tests that matter most in the app layer, because the gates are the app's
/// only guarantee that a user cannot reach a screening session without having been told
/// what the app does. Checking them per screen would mean trusting every future screen's
/// author to remember; checking them here means the guarantee holds for screens that do not
/// exist yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/data/auth_service.dart';
import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/features/auth/consent_screen.dart';
import 'package:neurascan_ai/features/auth/login_screen.dart';
import 'package:neurascan_ai/features/dashboard/dashboard_screen.dart';
import 'package:neurascan_ai/features/onboarding/onboarding_screen.dart';
import 'package:neurascan_ai/features/onboarding/splash_screen.dart';

import 'test_harness.dart';

void main() {
  group('signed out', () {
    testWidgets('lands on the onboarding, not stranded on the splash screen', (
      tester,
    ) async {
      // The splash screen is a loading state. Leaving a signed-out user sitting on it was a
      // real bug: its progress indicator spins forever and there is no way off.
      await pumpApp(tester);
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('the onboarding explains the personal-baseline idea', (
      tester,
    ) async {
      // A user who does not know why the first seven sessions say nothing will conclude the
      // app is broken and stop before the baseline is set.
      await pumpApp(tester);
      // Page two of three.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Compared with you'), findsOneWidget);
    });

    testWidgets('skipping the onboarding reaches the sign-in screen', (
      tester,
    ) async {
      await pumpApp(tester);
      await reachLogin(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('cannot reach the dashboard', (tester) async {
      await pumpApp(tester);
      await reachLogin(tester);
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('signing in moves past the sign-in screen', (tester) async {
      final app = await pumpApp(tester);
      await reachLogin(tester);

      await tester.enterText(
        find.byType(TextFormField).first,
        'someone@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'a-password');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(app.auth.currentAccount, isNotNull);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('a failed sign-in shows the reason and stays put', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await reachLogin(tester);
      app.auth.nextFailure = AuthFailure.invalidCredentials;

      await tester.enterText(
        find.byType(TextFormField).first,
        'someone@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'wrong');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      // Test case TC1: an inline error and no navigation.
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('do not match an account'), findsOneWidget);
    });

    testWidgets('an invalid email is rejected before any network call', (
      tester,
    ) async {
      await pumpApp(tester);
      await reachLogin(tester);

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.enterText(find.byType(TextFormField).last, 'a-password');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('email address'), findsWidgets);
    });

    testWidgets('the sign-in screen says the app works offline', (
      tester,
    ) async {
      // Someone downloading a health app on a poor connection has no reason to assume
      // this, and the sign-in screen is where they would otherwise give up.
      await pumpApp(tester);
      await reachLogin(tester);
      expect(find.textContaining('without a connection'), findsOneWidget);
    });

    testWidgets('the sign-in screen carries the disclaimer', (tester) async {
      await pumpApp(tester);
      await reachLogin(tester);
      expect(find.textContaining('does not diagnose'), findsWidgets);
    });
  });

  group('signed in without consent', () {
    testWidgets('is held on the consent screen', (tester) async {
      await pumpApp(tester, signedIn: consentPendingAccount);
      expect(find.byType(ConsentScreen), findsOneWidget);
    });

    testWidgets('cannot reach the dashboard', (tester) async {
      await pumpApp(tester, signedIn: consentPendingAccount);
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('the continue button is disabled until the box is ticked', (
      tester,
    ) async {
      // Test case TC2. Consent that can be given by tapping past a screen is not consent.
      await pumpApp(tester, signedIn: consentPendingAccount);

      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Continue'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'ticking the box enables it, and accepting reaches the dashboard',
      (tester) async {
        await pumpApp(tester, signedIn: consentPendingAccount);

        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();

        final button = tester.widget<FilledButton>(
          find.ancestor(
            of: find.text('Continue'),
            matching: find.byType(FilledButton),
          ),
        );
        expect(button.onPressed, isNotNull);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.byType(DashboardScreen), findsOneWidget);
      },
    );

    testWidgets('backup is off by default', (tester) async {
      // The only defensible default for health-related data, and the honest one: the app
      // is fully usable without it.
      await pumpApp(tester, signedIn: consentPendingAccount);
      expect(find.text('Keep everything on this phone only'), findsOneWidget);

      final selected = tester
          .widgetList<RadioListTile<bool>>(find.byType(RadioListTile<bool>))
          .toList();
      expect(selected, hasLength(2));
    });

    testWidgets('consent records the sync choice', (tester) async {
      final app = await pumpApp(tester, signedIn: consentPendingAccount);

      await tester.tap(find.text('Back up my measurements'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final profile = await app.repository.loadProfile('user-1');
      expect(profile!.syncEnabled, isTrue);
    });

    testWidgets('consent records the chosen hand', (tester) async {
      final app = await pumpApp(tester, signedIn: consentPendingAccount);

      await tester.tap(find.text('Left hand'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      final profile = await app.repository.loadProfile('user-1');
      expect(profile!.dominantHand.key, 'left');
    });

    testWidgets('the consent screen states what the app does not do', (
      tester,
    ) async {
      await pumpApp(tester, signedIn: consentPendingAccount);
      expect(find.textContaining('does not diagnose'), findsWidgets);
      expect(find.textContaining('replace a doctor'), findsOneWidget);
    });
  });

  group('signed in with consent', () {
    testWidgets('lands on the dashboard', (tester) async {
      final app = await pumpApp(tester, signedIn: consentPendingAccount);
      await completeOnboarding(app);
      await tester.pumpAndSettle();

      expect(find.byType(DashboardScreen), findsOneWidget);
    });

    testWidgets('signing out returns to the sign-in screen', (tester) async {
      final app = await pumpApp(tester, signedIn: consentPendingAccount);
      await completeOnboarding(app);
      await tester.pumpAndSettle();

      await app.auth.signOut();
      await tester.pumpAndSettle();

      // Straight to sign-in, not the onboarding: someone who has been through it once and
      // is returning does not need the introduction again.
      expect(find.byType(DashboardScreen), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('a stale consent version reopens the gate', (tester) async {
      // Consent to an earlier description of what the app does is not consent to a later
      // one, so a version bump must send the user back through the screen.
      final app = await pumpApp(tester, signedIn: consentPendingAccount);
      final profile = await completeOnboarding(app);
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsOneWidget);

      // Written through the repository so the profile stream emits. A raw SQL update does
      // not tell Drift which table changed, so the router would never have re-evaluated.
      await app.repository.saveProfile(
        profile.copyWith(
          consent: ConsentRecord(
            version: ConsentRecord.currentVersion - 1,
            acceptedAt: DateTime.utc(2026),
            syncEnabled: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ConsentScreen), findsOneWidget);
    });
  });

  group('splash', () {
    testWidgets('is shown before the stored session has been read', (
      tester,
    ) async {
      // Redirecting to sign-in during this window would flash the login screen at every
      // launch for a user who is already signed in.
      await pumpApp(tester, signedIn: consentPendingAccount, settle: false);
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('gives way once the session has loaded', (tester) async {
      await pumpApp(tester, signedIn: consentPendingAccount);
      expect(find.byType(SplashScreen), findsNothing);
    });
  });
}
